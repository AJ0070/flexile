import { db } from "@test/db";
import { companiesFactory } from "@test/factories/companies";
import { usersFactory } from "@test/factories/users";
import { companyLawyers } from "@/db/schema";

export const companyLawyersFactory = {
  create: async (overrides: Partial<typeof companyLawyers.$inferInsert> = {}) => {
    const [companyLawyer] = await db
      .insert(companyLawyers)
      .values({
        companyId: overrides.companyId || (await companiesFactory.create()).company.id,
        userId: overrides.userId || (await usersFactory.create()).user.id,
        ...overrides,
      })
      .returning();

    return { companyLawyer };
  },
};
