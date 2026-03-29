# Changelog

## [0.1.0] - 2026-03-29

### Added
- Initial release of YouTube search Tcl module
- CLI utility for searching YouTube videos
- Support for YouTube Data API v3
- Query URL encoding and safe JSON parsing
- Tcl library interface for programmatic use
- YOUTUBE_API_KEY environment variable configuration
- Configurable result limit (1-50 videos)
- Error handling for API errors and network issues

### Features
- Search videos by query text
- Display title and watch URL for each result
- Support both CLI and library usage modes
- Chunked data parsing without regex complexity
- Basic JSON content extraction with unescaping

### Requirements
- Tcl 8.6+
- curl
- YouTube Data API v3 key
