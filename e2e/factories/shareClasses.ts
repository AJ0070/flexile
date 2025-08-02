import { db } from "@test/db";
import { companiesFactory } from "@test/factories/companies";
import { shareClasses } from "@/db/schema";
import { assert } from "@/utils/assert";

let shareClassCounter = 0;

export const shareClassesFactory = {
  create: async (overrides: Partial<typeof shareClasses.$inferInsert> = {}) => {
    shareClassCounter++;
    const [shareClass] = await db
      .insert(shareClasses)
      .values({
        companyId: overrides.companyId || (await companiesFactory.create()).company.id,
        name: overrides.name || `Common${shareClassCounter}`,
        originalIssuePriceInDollars: overrides.originalIssuePriceInDollars || "0.2345",
        hurdleRate: overrides.hurdleRate || "8.37",
        ...overrides,
      })
      .returning();
    assert(shareClass != null);

    return { shareClass };
  },
};
