use image::imageops::FilterType;
use std::io::Cursor;
use xcap::Monitor;

/// Claude's vision tile is 1568×1568; anything larger gets split into multiple
/// tiles (more tokens, more latency). Downscale before send.
const MAX_DIMENSION: u32 = 1568;

#[derive(Debug, Clone)]
pub struct CapturedScreen {
    pub bytes: Vec<u8>,
    /// 모델에 실제로 보낸 (다운스케일 후) 픽셀 크기. 모델 좌표 응답의
    /// 기준 좌표계.
    pub sent_size: (u32, u32),
    /// 캡처 시점 monitor의 원본 픽셀 크기. overlay를 그릴 좌표계 — 모델
    /// coords에 orig/sent ratio를 곱해 변환 필요.
    pub orig_size: (u32, u32),
}

#[derive(Debug)]
pub enum CaptureError {
    NoMonitor,
    XCap(String),
    Encode(String),
}

impl std::fmt::Display for CaptureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoMonitor => write!(f, "no monitor available"),
            Self::XCap(e) => write!(f, "xcap: {e}"),
            Self::Encode(e) => write!(f, "encode: {e}"),
        }
    }
}

impl std::error::Error for CaptureError {}

/// Capture the primary monitor. macOS asks for Screen Recording permission
/// the first time. Returns both bytes and dimensions so the analyze pipeline
/// can scale model-relative coordinates back to monitor coords.
pub fn capture_active_screen() -> Result<CapturedScreen, CaptureError> {
    let monitors = Monitor::all().map_err(|e| CaptureError::XCap(e.to_string()))?;
    let monitor = monitors
        .iter()
        .find(|m| m.is_primary().unwrap_or(false))
        .or_else(|| monitors.first())
        .ok_or(CaptureError::NoMonitor)?;

    let img = monitor
        .capture_image()
        .map_err(|e| CaptureError::XCap(e.to_string()))?;

    let (orig_w, orig_h) = (img.width(), img.height());

    let scaled = if orig_w > MAX_DIMENSION || orig_h > MAX_DIMENSION {
        // Lanczos3 keeps small UI text legible better than Triangle/Nearest.
        let dyn_img = image::DynamicImage::ImageRgba8(img);
        let resized = dyn_img.resize(MAX_DIMENSION, MAX_DIMENSION, FilterType::Lanczos3);
        resized.to_rgba8()
    } else {
        img
    };

    let (sent_w, sent_h) = (scaled.width(), scaled.height());
    let mut bytes = Vec::new();
    scaled
        .write_to(&mut Cursor::new(&mut bytes), image::ImageFormat::Png)
        .map_err(|e| CaptureError::Encode(e.to_string()))?;

    tracing::info!(
        target: "capture",
        "captured: orig={}x{}, sent={}x{}, bytes={}",
        orig_w,
        orig_h,
        sent_w,
        sent_h,
        bytes.len()
    );

    Ok(CapturedScreen {
        bytes,
        sent_size: (sent_w, sent_h),
        orig_size: (orig_w, orig_h),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // Ignored by default because macOS pops a Screen Recording permission
    // dialog the first time. Run with `cargo test -- --ignored` after the
    // permission is granted in System Settings.
    #[test]
    #[ignore = "needs macOS Screen Recording permission"]
    fn capture_active_screen_smoke() {
        let cap = capture_active_screen().expect("capture should succeed");
        assert!(cap.bytes.len() > 1024, "captured {} bytes (< 1KB)", cap.bytes.len());
        assert_eq!(
            &cap.bytes[..8],
            &[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a],
            "missing PNG signature"
        );
        assert!(cap.sent_size.0 <= MAX_DIMENSION && cap.sent_size.1 <= MAX_DIMENSION);
        assert!(cap.orig_size.0 > 0 && cap.orig_size.1 > 0);
    }
}
