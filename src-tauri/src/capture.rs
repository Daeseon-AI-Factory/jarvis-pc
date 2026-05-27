use core_graphics::event::CGEvent;
use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};
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
    /// 캡처 시점 monitor의 원본 픽셀 크기 (그 monitor 안 local px).
    pub orig_size: (u32, u32),
    /// 캡처한 monitor의 전역 좌표계 position (multi-monitor 환경에서 다른
    /// monitor와 구분). overlay setPosition에 그대로 사용.
    pub monitor_position: (i32, i32),
}

/// macOS의 NSEvent.mouseLocation을 core-graphics로 받는다. 좌표는 *bottom-left
/// origin* 기준 (NSPoint 관례) — Y축 flip 필요. 또 모든 단위가 *logical px*.
/// multi-monitor 환경에서 cursor 있는 monitor를 결정하기 위해 호출.
fn cursor_position_logical() -> Option<(f64, f64)> {
    let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState).ok()?;
    let event = CGEvent::new(source).ok()?;
    let p = event.location();
    Some((p.x, p.y))
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

/// Capture the monitor under the mouse cursor (multi-monitor friendly).
/// Falls back to primary if cursor monitor can't be resolved. macOS asks for
/// Screen Recording permission the first time.
pub fn capture_active_screen() -> Result<CapturedScreen, CaptureError> {
    let monitors = Monitor::all().map_err(|e| CaptureError::XCap(e.to_string()))?;

    // 1. cursor 위치 → 그 monitor.
    // 2. 못 받으면 is_primary().
    // 3. 그것도 안 되면 monitors[0].
    let cursor_monitor = cursor_position_logical().and_then(|(x, y)| {
        // Monitor::from_point는 cursor의 logical px 받아 그 안의 monitor 찾는다.
        Monitor::from_point(x as i32, y as i32).ok()
    });
    let monitor_owned;
    let monitor: &Monitor = if let Some(m) = cursor_monitor.as_ref() {
        m
    } else {
        monitor_owned = monitors
            .iter()
            .find(|m| m.is_primary().unwrap_or(false))
            .or_else(|| monitors.first())
            .ok_or(CaptureError::NoMonitor)?;
        monitor_owned
    };

    let monitor_x = monitor.x().unwrap_or(0);
    let monitor_y = monitor.y().unwrap_or(0);

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
        "captured: monitor_pos=({},{}) orig={}x{} sent={}x{} bytes={}",
        monitor_x,
        monitor_y,
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
        monitor_position: (monitor_x, monitor_y),
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
