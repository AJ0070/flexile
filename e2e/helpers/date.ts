import { endOfWeek, startOfWeek } from "date-fns";

const WEEK_START_DAY = 0; // 0 = Sunday

export const startsOn = (date: Date) => startOfWeek(date, { weekStartsOn: WEEK_START_DAY });
export const endsOn = (date: Date) => endOfWeek(date, { weekStartsOn: WEEK_START_DAY });
