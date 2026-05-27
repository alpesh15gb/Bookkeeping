import React, { Suspense } from "react";

const ChartInternal = React.lazy(() => import("./SyncfusionChartInternal"));

interface ChartSeries {
  type: "Line" | "Column" | "Area" | "Spline" | "Bar" | "Pie" | "Doughnut";
  dataSource: any[];
  xName: string;
  yName: string;
  name?: string;
  fill?: string;
  marker?: {
    visible: boolean;
    dataLabel: { visible: boolean; format?: string };
  };
}

interface ChartAxis {
  title?: string;
  labelFormat?: string;
}

interface SyncfusionChartProps {
  series: ChartSeries[];
  title?: string;
  height?: string;
  width?: string;
  primaryXAxis?: ChartAxis;
  primaryYAxis?: ChartAxis;
  tooltip?: { visible: boolean; format?: string };
  legendSettings?: {
    visible: boolean;
    position?: "Top" | "Bottom" | "Left" | "Right";
  };
}

export default function SyncfusionChart(props: SyncfusionChartProps) {
  return (
    <Suspense
      fallback={
        <div className="flex justify-center items-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" />
        </div>
      }
    >
      <ChartInternal {...props} />
    </Suspense>
  );
}
