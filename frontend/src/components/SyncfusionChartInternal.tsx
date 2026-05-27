import React from "react";
import {
  ChartComponent,
  SeriesDirective,
  SeriesCollectionDirective,
  AccumulationChartComponent,
  AccumulationSeriesDirective,
  AccumulationSeriesCollectionDirective,
  Inject,
} from "@syncfusion/ej2-react-charts";
import {
  LineSeries,
  ColumnSeries,
  AreaSeries,
  SplineSeries,
  BarSeries,
  PieSeries,
  Tooltip,
  Legend,
  Category,
  DateTime,
  Logarithmic,
  AccumulationTooltip,
  AccumulationLegend,
  AccumulationDataLabel,
} from "@syncfusion/ej2-charts";
import "../lib/syncfusion";

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

interface ChartInternalProps {
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

export default function SyncfusionChartInternal(props: ChartInternalProps) {
  const cartesian = props.series.filter(
    (s) => s.type !== "Pie" && s.type !== "Doughnut"
  );
  const accumulation = props.series.filter(
    (s) => s.type === "Pie" || s.type === "Doughnut"
  );

  return (
    <div className="space-y-4">
      {cartesian.length > 0 && (
        <ChartComponent
          title={cartesian.length === props.series.length ? props.title : undefined}
          height={props.height || "300"}
          width={props.width || "100%"}
          primaryXAxis={props.primaryXAxis || { title: "" }}
          primaryYAxis={
            props.primaryYAxis || { title: "", labelFormat: "c" }
          }
          tooltip={
            props.tooltip || {
              visible: true,
              format: "${point.x} : ₹${point.y}",
            }
          }
          legendSettings={
            props.legendSettings || { visible: true, position: "Bottom" }
          }
        >
          <Inject
            services={[
              LineSeries,
              ColumnSeries,
              AreaSeries,
              SplineSeries,
              BarSeries,
              Tooltip,
              Legend,
              Category,
              DateTime,
              Logarithmic,
            ]}
          />
          <SeriesCollectionDirective>
            {cartesian.map((s, i) => (
              <SeriesDirective
                key={i}
                type={s.type as any}
                dataSource={s.dataSource}
                xName={s.xName}
                yName={s.yName}
                name={s.name || ""}
                fill={s.fill}
                marker={
                  s.marker || {
                    visible: true,
                    dataLabel: { visible: true, format: "${point.y}" },
                  }
                }
              />
            ))}
          </SeriesCollectionDirective>
        </ChartComponent>
      )}
      {accumulation.length > 0 && (
        <AccumulationChartComponent
          title={accumulation.length === props.series.length ? props.title : undefined}
          height={props.height || "300"}
          width={props.width || "100%"}
          tooltip={
            props.tooltip || {
              visible: true,
              format: "${point.x} : ₹${point.y}",
            }
          }
          legendSettings={
            props.legendSettings || { visible: true, position: "Bottom" }
          }
        >
          <Inject
            services={[
              PieSeries,
              AccumulationTooltip,
              AccumulationLegend,
              AccumulationDataLabel,
            ]}
          />
          <AccumulationSeriesCollectionDirective>
            {accumulation.map((s, i) => (
              <AccumulationSeriesDirective
                key={i}
                type="Pie"
                dataSource={s.dataSource}
                xName={s.xName}
                yName={s.yName}
                name={s.name || ""}
                dataLabel={{
                  visible: true,
                  format: "${point.x} : ${point.y}",
                }}
              />
            ))}
          </AccumulationSeriesCollectionDirective>
        </AccumulationChartComponent>
      )}
    </div>
  );
}
