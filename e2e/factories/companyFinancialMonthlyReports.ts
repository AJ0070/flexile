import assert from "node:assert";
import { faker } from "@faker-js/faker";
import { db } from "@test/db";
import { companiesFactory } from "@test/factories/companies";
import { companyMonthlyFinancialReports } from "@/db/schema";

export const companyMonthlyFinancialReportsFactory = {
  create: async (overrides: Partial<typeof companyMonthlyFinancialReports.$inferInsert> = {}) => {
    const [report] = await db
      .insert(companyMonthlyFinancialReports)
      .values({
        companyId: overrides.companyId ?? (await companiesFactory.create()).company.id,
        year: new Date().getFullYear(),
        month: new Date().getMonth() + 1,
        netIncomeCents: faker.number.bigInt({ min: -1000_00, max: 1000_00 }),
        revenueCents: faker.number.bigInt({ min: -500_00, max: 500_00 }),
        ...overrides,
      })
      .returning();
    assert(report != null);

    return { report };
  },

  createForAYear: async (overrides: Partial<typeof companyMonthlyFinancialReports.$inferInsert> = {}) => {
    assert(typeof overrides.year === "number");
    assert(overrides.month === undefined);

    const reports = [];
    for (let month = 1; month <= 12; month++) {
      const report = await companyMonthlyFinancialReportsFactory.create({ ...overrides, month });
      reports.push(report);
    }

    return { reports };
  },
};
