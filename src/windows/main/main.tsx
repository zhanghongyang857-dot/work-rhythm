import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "../../styles.css";
import { MainWindow } from "./MainWindow";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <MainWindow />
  </StrictMode>,
);
