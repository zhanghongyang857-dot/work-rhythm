import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "../../styles.css";
import { MiniTimer } from "./MiniTimer";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <MiniTimer />
  </StrictMode>,
);
