import React, { useRef, useEffect, useCallback } from "react";

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

interface SyncfusionGridProps {
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
  search?: { key: string; fields?: string[]; operator?: string; ignoreCase?: boolean };
  children?: React.ReactNode;
}

export default function SyncfusionGrid(props: SyncfusionGridProps) {
  const gridRef = useRef<any>(null);
  const [Grid, setGrid] = React.useState<any>(null);
  const [ColumnDirective, setColumnDirective] = React.useState<any>(null);
  const [ColumnsDirective, setColumnsDirective] = React.useState<any>(null);
  const [Inject, setInject] = React.useState<any>(null);
  const [services, setServices] = React.useState<any[]>([]);
  const [mounted, setMounted] = React.useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      await import("../lib/syncfusion");
      const [
        { GridComponent, ColumnsDirective: CD, ColumnDirective: ColD },
        { Page, Sort, Filter, Group, ExcelExport, PdfExport, Search: SfSearch, Toolbar },
      ] = await Promise.all([
        import("@syncfusion/ej2-react-grids"),
        import("@syncfusion/ej2-grids"),
      ]);
      if (cancelled) return;
      setGrid(() => GridComponent);
      setColumnDirective(() => ColD);
      setColumnsDirective(() => CD);
      setInject(() => Inject);
      setServices([Page, Sort, Filter, Group, ExcelExport, PdfExport, SfSearch, Toolbar].filter(Boolean));
      setMounted(true);
    })();
    return () => { cancelled = true; };
  }, []);

  if (!mounted || !Grid) {
    return (
      <div className="flex justify-center items-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  return React.createElement(Grid, {
    ref: gridRef,
    dataSource: props.dataSource,
    allowPaging: props.allowPaging ?? true,
    allowSorting: props.allowSorting ?? true,
    allowFiltering: props.allowFiltering ?? false,
    allowGrouping: props.allowGrouping ?? false,
    allowExcelExport: props.allowExcelExport ?? false,
    allowPdfExport: props.allowPdfExport ?? false,
    toolbar: props.toolbar,
    pageSettings: props.pageSettings ?? { pageSize: 20, pageSizes: [10, 20, 50, 100] },
    height: props.height ?? "auto",
    width: "100%",
    children: React.createElement(
      ColumnsDirective,
      null,
      ...(props.columns || []).map((col, i) =>
        React.createElement(ColumnDirective, {
          key: i,
          field: col.field,
          headerText: col.headerText,
          width: col.width,
          format: col.format,
          textAlign: col.textAlign || "Left",
          clipMode: col.clipMode || "EllipsisWithTooltip",
          visible: col.visible !== false,
          customAttributes: col.customAttributes,
        })
      ),
      props.children
    ),
  });
}
