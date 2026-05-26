use std::io::Cursor;
use xcap::Monitor;

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

/// Capture the primary monitor and return the PNG bytes. macOS asks for
/// Screen Recording permission the first time this runs.
pub fn capture_active_screen() -> Result<Vec<u8>, CaptureError> {
    let monitors = Monitor::all().map_err(|e| CaptureError::XCap(e.to_string()))?;
    let monitor = monitors
        .iter()
        .find(|m| m.is_primary().unwrap_or(false))
        .or_else(|| monitors.first())
        .ok_or(CaptureError::NoMonitor)?;

    let img = monitor
        .capture_image()
        .map_err(|e| CaptureError::XCap(e.to_string()))?;

    let (w, h) = (img.width(), img.height());
    let mut bytes = Vec::new();
    img.write_to(&mut Cursor::new(&mut bytes), image::ImageFormat::Png)
        .map_err(|e| CaptureError::Encode(e.to_string()))?;

    tracing::info!(
        target: "capture",
        "captured: bytes={}, {}x{}",
        bytes.len(),
        w,
        h
    );

    Ok(bytes)
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
        let bytes = capture_active_screen().expect("capture should succeed");
        assert!(bytes.len() > 1024, "captured {} bytes (< 1KB)", bytes.len());
        assert_eq!(
            &bytes[..8],
            &[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a],
            "missing PNG signature"
        );
    }
}
