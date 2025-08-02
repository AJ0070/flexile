import { db } from "@test/db";
import { companiesFactory } from "@test/factories/companies";
import { usersFactory } from "@test/factories/users";
import { companyAdministrators } from "@/db/schema";
import { assert } from "@/utils/assert";

export const companyAdministratorsFactory = {
  create: async (overrides: Partial<typeof companyAdministrators.$inferInsert> = {}) => {
    const [administrator] = await db
      .insert(companyAdministrators)
      .values({
        companyId: overrides.companyId || (await companiesFactory.create()).company.id,
        userId: overrides.userId || (await usersFactory.create()).user.id,
        ...overrides,
      })
      .returning();
    assert(administrator != null);

    return { administrator };
  },

  createPreOnboarding: async (overrides: Partial<typeof companyAdministrators.$inferInsert> = {}) => {
    const { company } = await companiesFactory.createPreOnboarding();
    return companyAdministratorsFactory.create({
      companyId: company.id,
      ...overrides,
    });
  },
};
