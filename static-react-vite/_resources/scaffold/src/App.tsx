import "./App.css";

function App() {
  return (
    <main>
      <article className="card">
        <div className="badge">PartRocks template</div>
        <h1>Your new React + Vite application</h1>
        <p>
          This project was generated from the PartRocks{" "}
          <strong>static-react-vite</strong> catalog template. You have a working
          React app with <strong>Vite</strong> and <strong>TypeScript</strong>,
          with Docker-based local development and AWS S3 static hosting presets when
          you deploy.
        </p>
        <p>
          <strong>Quick start:</strong> from the project root, start the dev stack
          with Docker Compose (dev environment in PartRocks), then open this page at
          the mapped port. Or run <code>npm install</code> and{" "}
          <code>npm run dev</code> locally.
        </p>
        <ul>
          <li>
            <strong>React</strong> + <strong>Vite</strong> (TypeScript template)
          </li>
          <li>
            <strong>Dev server</strong> listens on port{" "}
            <code>5173</code> in the container
          </li>
          <li>
            Production builds output to <code>dist/</code>; commit that folder
            before tagging a release for S3 sync (see template notes).
          </li>
          <li>
            Replace this landing page in <code>src/App.tsx</code> and{" "}
            <code>src/App.css</code> when you are ready.
          </li>
        </ul>
        <footer>
          Cloud presets use S3 website hosting (minimal HTTP or shared gateway /
          TLS at the edge).
        </footer>
      </article>
    </main>
  );
}

export default App;
