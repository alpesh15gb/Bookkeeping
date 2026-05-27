import React from "react";
import {
  ScheduleComponent,
  ViewsDirective,
  ViewDirective,
  Inject,
  Day,
  Week,
  Month,
  Agenda,
} from "@syncfusion/ej2-react-schedule";
import "../../lib/syncfusion";

interface ScheduleInternalProps {
  events: any[];
}

export default function ScheduleInternal({ events }: ScheduleInternalProps) {
  return (
    <ScheduleComponent
      height="600px"
      selectedDate={new Date()}
      eventSettings={{ dataSource: events }}
    >
      <ViewsDirective>
        <ViewDirective option="Day" />
        <ViewDirective option="Week" />
        <ViewDirective option="Month" />
        <ViewDirective option="Agenda" />
      </ViewsDirective>
      <Inject services={[Day, Week, Month, Agenda]} />
    </ScheduleComponent>
  );
}
