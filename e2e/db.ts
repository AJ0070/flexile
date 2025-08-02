import { drizzle } from "drizzle-orm/node-postgres";
import { z } from "zod";
import * as schema from "@/db/schema";

const DATABASE_URL = z.string().parse(process.env.DATABASE_URL);

export const db = drizzle({
  connection: DATABASE_URL,
  schema,
});

export const takeOrThrow = <T>(value: T | null | undefined): T => {
  if (!value) {
    throw new Error("Record not found");
  }
  return value;
};
