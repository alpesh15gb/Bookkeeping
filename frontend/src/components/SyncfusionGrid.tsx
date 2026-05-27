import React, { Suspense } from "react";

const GridInternal = React.lazy(() => import("./SyncfusionGridInternal"));

export interface SyncfusionGridColumn {
  field: string;
  headerText: string;
  width?: string;
  format?: string;
  type?: "number" | "string" | "date" | "boolean";
  textAlign?: "Left" | "Right" | "Center";
  allowEditing?: boolean;
  editType?: "numericedit" | "stringedit" | "datepickeredit" | "booleanedit" | "dropdownedit";
  editParams?: Record<string, any>;
  edit?: (args: any) => void;
  customAttributes?: Record<string, string>;
  visible?: boolean;
  clipMode?: "Ellipsis" | "Clip" | "EllipsisWithTooltip";
  template?: string;
}

export interface SyncfusionGridProps {
  dataSource: any[];
  columns: SyncfusionGridColumn[];
  height?: string | number;
  allowPaging?: boolean;
  allowSorting?: boolean;
  allowFiltering?: boolean;
  allowGrouping?: boolean;
  allowExcelExport?: boolean;
  allowPdfExport?: boolean;
  toolbar?: string[];
  pageSettings?: { pageSize: number; pageSizes?: boolean | number[] };
  children?: React.ReactNode;
}

export default function SyncfusionGrid(props: SyncfusionGridProps) {
  return (
    <Suspense
      fallback={
        <div className="flex justify-center items-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" />
        </div>
      }
    >
      <GridInternal {...props} />
    </Suspense>
  );
}
