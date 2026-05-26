import { useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import TriggerPanel from "./components/TriggerPanel";
import Overlay from "./components/Overlay";
import "./App.css";

export default function App() {
  const [label, setLabel] = useState<string | null>(null);
  useEffect(() => {
    setLabel(getCurrentWindow().label);
  }, []);
  if (label === null) return null;
  return label === "overlay" ? <Overlay /> : <TriggerPanel />;
}
