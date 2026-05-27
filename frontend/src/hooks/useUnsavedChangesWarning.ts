import { useEffect } from "react";
import { useDirtyStore } from "./useDirtyStore";

export function useUnsavedChangesWarning(hasUnsavedChanges: boolean) {
  const setDirty = useDirtyStore((s) => s.setDirty);

  useEffect(() => {
    setDirty(hasUnsavedChanges);
  }, [hasUnsavedChanges, setDirty]);

  useEffect(() => {
    const handler = (e: BeforeUnloadEvent) => {
      if (hasUnsavedChanges) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", handler);
    return () => window.removeEventListener("beforeunload", handler);
  }, [hasUnsavedChanges]);
}
