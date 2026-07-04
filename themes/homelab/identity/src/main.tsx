import { createRoot } from "react-dom/client";
import { KcPage } from "./kc.gen";

const kcContext = (window as any).kcContext;

if (kcContext !== undefined) {
  createRoot(document.getElementById("root")!).render(<KcPage kcContext={kcContext} />);
}
