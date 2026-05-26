import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { logBackend } from "./lib/ipc";

void logBackend("info", "frontend bootstrapping");

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
