import React, { useEffect, useState } from "react";

interface ChartSeries {
  type: "Line" | "Column" | "Area" | "Spline" | "Bar" | "Pie" | "Doughnut";
  dataSource: any[];
  xName: string;
  yName: string;
  name?: string;
  fill?: string;
  marker?: { visible: boolean; dataLabel: { visible: boolean; format?: string } };
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
  legendSettings?: { visible: boolean; position?: "Top" | "Bottom" | "Left" | "Right" };
}

export default function SyncfusionChart(props: SyncfusionChartProps) {
  const [ChartComponent, setChartComponent] = useState<any>(null);
  const [SeriesDirective, setSeriesDirective] = useState<any>(null);
  const [SeriesCollectionDirective, setSeriesCollectionDirective] = useState<any>(null);
  const [Inject, setInject] = useState<any>(null);
  const [chartServices, setChartServices] = useState<any[]>([]);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      await import("../lib/syncfusion");
      const [
        { ChartComponent: CC, SeriesDirective: SD, SeriesCollectionDirective: SCD, Inject: Inj },
        { LineSeries, ColumnSeries, AreaSeries, SplineSeries, BarSeries, PieSeries, AccumulationPieSeries, AccumulationToolbar, Tooltip, Legend, Category, DateTime, Logarithmic },
      ] = await Promise.all([
        import("@syncfusion/ej2-react-charts"),
        import("@syncfusion/ej2-charts"),
      ]);
      if (cancelled) return;
      setChartComponent(() => CC);
      setSeriesDirective(() => SD);
      setSeriesCollectionDirective(() => SCD);
      setInject(() => Inj);
      setChartServices([
        LineSeries, ColumnSeries, AreaSeries, SplineSeries, BarSeries, 
        PieSeries, AccumulationPieSeries, AccumulationToolbar, 
        Tooltip, Legend, Category, DateTime, Logarithmic
      ]);
      setMounted(true);
    })();
    return () => { cancelled = true; };
  }, []);

  if (!mounted || !ChartComponent) {
    return (
      <div className="flex justify-center items-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  return React.createElement("div", { className: "w-full" },
    React.createElement(ChartComponent, {
      title: props.title,
      height: props.height || "300",
      width: props.width || "100%",
      primaryXAxis: props.primaryXAxis || { title: "" },
      primaryYAxis: props.primaryYAxis || { title: "", labelFormat: "c" },
      tooltip: props.tooltip || { visible: true, format: "${point.x} : ₹${point.y}" },
      legendSettings: props.legendSettings || { visible: true, position: "Bottom" },
    },
      React.createElement(Inject, null, ...chartServices),
      React.createElement(
        SeriesCollectionDirective,
        null,
        ...(props.series || []).map((s, i) =>
          React.createElement(SeriesDirective, {
            key: i,
            type: s.type === "Doughnut" ? "Pie" : s.type,
            dataSource: s.dataSource,
            xName: s.xName,
            yName: s.yName,
            name: s.name || "",
            fill: s.fill,
            marker: s.marker || { visible: true, dataLabel: { visible: true, format: "${point.y}" } },
          })
        )
      )
    )
  );
}
