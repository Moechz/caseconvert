# Changelog

## 1.0.0-1 — 2026-09-27

### Added
- First release of **Case Converter for TerraMaster TOS 7** as a Docker
  application. Convert text between sentence case, title case, capital case,
  lower case and upper case, with live word and character counts.
- The web page is embedded in `docker-compose.yml`, so the application is fully
  offline: the only download at install time is the nginx image from Docker Hub.
- 23-language description file (`caseconvert.lang`).
- Bilingual privacy policy for the offline app.

### Changed (relative to the upstream website)
- Removed Google Analytics and Google AdSense.
- Removed the external Formspree contact form.
- Rewrote links to `caseconverter.cc` as relative pages.
- Removed the unused social-preview images (the site now needs only the page
  files, the favicon and one inline image).

### Notes
- Runs as a non-root user (`1000:1000`) on a fixed
  `nginxinc/nginx-unprivileged:1.27-alpine` image.
- Based on the MIT-licensed upstream project
  <https://github.com/caseconverter/caseconverter>.
