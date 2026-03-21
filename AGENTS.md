# Repo Rules

## Live Media UI Safety

- Treat camera and movie imagery as the primary output surface. Do not place operator panels, sliders, or scrollable cards on top of the live preview by default.
- For monitoring and operation, prefer separate surfaces: `Operator Console` for controls and a dedicated `Monitor` page or window for the clean input image.
- If a page contains both controls and preview, define the preview rectangle first and keep every control outside that rectangle.
- Session polling and UI refresh must be idempotent for capture sources. Never call `getUserMedia`, recreate a `MediaStream`, or replace `video.src` unless the capture source signature changed.
- Use a stable source signature for preview reuse: at minimum include source mode, camera index or video path, and loop or mirror flags.
- Any periodic sync logic must preserve the active preview stream and must not introduce black flashes, renegotiation noise, or permission churn.
