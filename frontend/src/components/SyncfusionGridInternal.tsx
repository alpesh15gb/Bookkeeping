import React from "react";
import {
  GridComponent,
  ColumnsDirective,
  ColumnDirective,
  Inject,
} from "@syncfusion/ej2-react-grids";
import {
  Page,
  Sort,
  Filter,
  Group,
  ExcelExport,
  PdfExport,
  Search as GridSearch,
  Toolbar,
} from "@syncfusion/ej2-grids";
import "../lib/syncfusion";

interface SyncfusionGridColumn {
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

interface GridInternalProps {
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

export default function SyncfusionGridInternal(props: GridInternalProps) {
  return (
    <GridComponent
      ref={(ref: any) => {
        if (ref) (window as any).__gridRef = ref;
      }}
      dataSource={props.dataSource}
      allowPaging={props.allowPaging ?? true}
      allowSorting={props.allowSorting ?? true}
      allowFiltering={props.allowFiltering ?? false}
      allowGrouping={props.allowGrouping ?? false}
      allowExcelExport={props.allowExcelExport ?? false}
      allowPdfExport={props.allowPdfExport ?? false}
      toolbar={props.toolbar}
      pageSettings={
        props.pageSettings ?? { pageSize: 20, pageSizes: [10, 20, 50, 100] }
      }
      height={props.height ?? "auto"}
      width="100%"
    >
      <ColumnsDirective>
        {(props.columns || []).map((col, i) => (
          <ColumnDirective
            key={i}
            field={col.field}
            headerText={col.headerText}
            width={col.width}
            format={col.format}
            textAlign={col.textAlign || "Left"}
            clipMode={col.clipMode || "EllipsisWithTooltip"}
            visible={col.visible !== false}
            customAttributes={col.customAttributes}
          />
        ))}
        {props.children}
      </ColumnsDirective>
      <Inject services={[Page, Sort, Filter, Group, ExcelExport, PdfExport, GridSearch, Toolbar]} />
    </GridComponent>
  );
}
