# Static HTML Site

This app starts with a simple static website structure:

- `index.html`
- `css/styles.css`
- `js/app.js`

## Local preview

From this app directory, run:

```bash
python3 -m http.server 8080
```

Then open `http://localhost:8080`.

## AWS deployment

The template includes a low-cost OpenTofu target that creates:

- One public S3 bucket
- S3 static website hosting configuration
- Default static files (`index.html`, `css/styles.css`, `js/app.js`)

This is designed as the cheapest AWS baseline for static hosting.
