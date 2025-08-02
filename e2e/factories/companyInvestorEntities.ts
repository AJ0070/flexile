import { faker } from "@faker-js/faker";
import { db } from "@test/db";
import { companiesFactory } from "@test/factories/companies";
import { companyInvestorEntities } from "@/db/schema";
import { assert } from "@/utils/assert";

export const companyInvestorEntitiesFactory = {
  create: async (overrides: Partial<typeof companyInvestorEntities.$inferInsert> = {}) => {
    const [companyInvestorEntity] = await db
      .insert(companyInvestorEntities)
      .values({
        companyId: overrides.companyId || (await companiesFactory.create()).company.id,
        name: overrides.name || faker.person.fullName(),
        email: overrides.email || faker.internet.email().toLowerCase(),
        investmentAmountCents: overrides.investmentAmountCents || 0n,
        ...overrides,
      })
      .returning();
    assert(companyInvestorEntity != null);

    return { companyInvestorEntity };
  },
};
