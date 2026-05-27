import { create } from "zustand";

interface DirtyStore {
  isDirty: boolean;
  pendingConfirm: (() => void) | null;
  setDirty: (dirty: boolean) => void;
  setPendingConfirm: (fn: (() => void) | null) => void;
}

export const useDirtyStore = create<DirtyStore>((set) => ({
  isDirty: false,
  pendingConfirm: null,
  setDirty: (dirty) => set({ isDirty: dirty }),
  setPendingConfirm: (fn) => set({ pendingConfirm: fn }),
}));
