import { db, takeOrThrow } from "@test/db";
import { companyInvestorEntitiesFactory } from "@test/factories/companyInvestorEntities";
import { companyInvestorsFactory } from "@test/factories/companyInvestors";
import { optionPoolsFactory } from "@test/factories/optionPools";
import { addMonths, endOfDay, startOfDay, subDays } from "date-fns";
import { and, eq } from "drizzle-orm";
import { companyInvestorEntities, companyInvestors, equityGrants, optionPools, users } from "@/db/schema";
import { assert } from "@/utils/assert";

let grantCounter = 0;

type CreateOptions = {
  year: number;
};

const defaultOptions = { year: new Date().getFullYear() - 2 };

export const equityGrantsFactory = {
  create: async (
    overrides: Partial<typeof equityGrants.$inferInsert> = {},
    options: CreateOptions = defaultOptions,
  ) => {
    const investor = overrides.companyInvestorId
      ? await db.query.companyInvestors
          .findFirst({
            where: eq(companyInvestors.id, overrides.companyInvestorId),
            with: { user: true },
          })
          .then(takeOrThrow)
      : (await companyInvestorsFactory.create()).companyInvestor;

    const investorUser = await db.query.users
      .findFirst({
        where: eq(users.id, investor.userId),
      })
      .then(takeOrThrow);

    // companyInvestorEntity should have the same company and legalName as the investor
    const companyInvestorEntity = overrides.companyInvestorEntityId
      ? await db.query.companyInvestorEntities
          .findFirst({
            where: and(
              eq(companyInvestorEntities.id, overrides.companyInvestorEntityId),
              eq(companyInvestorEntities.companyId, investor.companyId),
              eq(companyInvestorEntities.name, investorUser.legalName ?? ""),
            ),
          })
          .then(takeOrThrow)
      : (
          await companyInvestorEntitiesFactory.create({
            companyId: investor.companyId,
            name: investorUser.legalName ?? "",
          })
        ).companyInvestorEntity;
    const optionPool = overrides.optionPoolId
      ? await db.query.optionPools
          .findFirst({
            where: and(eq(optionPools.id, overrides.optionPoolId), eq(optionPools.companyId, investor.companyId)),
          })
          .then(takeOrThrow)
      : (
          await optionPoolsFactory.create({
            companyId: investor.companyId,
          })
        ).optionPool;

    grantCounter++;

    const [equityGrant] = await db
      .insert(equityGrants)
      .values({
        companyInvestorId: investor.id,
        companyInvestorEntityId: companyInvestorEntity.id,
        optionPoolId: optionPool.id,
        name: overrides.name || `GUM-${grantCounter}`,
        numberOfShares: overrides.numberOfShares || 100,
        sharePriceUsd: overrides.sharePriceUsd || "10",
        exercisePriceUsd: overrides.exercisePriceUsd || "5",
        vestedShares: overrides.vestedShares || 100,
        unvestedShares: overrides.unvestedShares || 0,
        vestingTrigger: overrides.vestingTrigger || "invoice_paid",
        exercisedShares: overrides.exercisedShares || 0,
        forfeitedShares: overrides.forfeitedShares || 0,
        issuedAt: overrides.issuedAt || new Date(),
        expiresAt: overrides.expiresAt || addMonths(new Date(), optionPool.defaultOptionExpiryMonths),
        acceptedAt: overrides.acceptedAt || new Date(),
        optionHolderName: overrides.optionHolderName || (investorUser.legalName ?? ""),
        boardApprovalDate: overrides.boardApprovalDate || subDays(new Date(), 1).toDateString(),
        voluntaryTerminationExerciseMonths: overrides.voluntaryTerminationExerciseMonths || 120,
        involuntaryTerminationExerciseMonths: overrides.involuntaryTerminationExerciseMonths || 120,
        terminationWithCauseExerciseMonths: overrides.terminationWithCauseExerciseMonths || 0,
        deathExerciseMonths: overrides.deathExerciseMonths || 120,
        disabilityExerciseMonths: overrides.disabilityExerciseMonths || 120,
        retirementExerciseMonths: overrides.retirementExerciseMonths || 120,
        periodStartedAt: overrides.periodStartedAt || startOfDay(new Date(`${options.year}-01-01`)),
        periodEndedAt: overrides.periodEndedAt || endOfDay(new Date(`${options.year}-12-31`)),
        ...overrides,
      })
      .returning();
    assert(equityGrant != null);

    return { equityGrant };
  },

  createActive: async (
    overrides: Partial<typeof equityGrants.$inferInsert> = {},
    options: CreateOptions = defaultOptions,
  ) =>
    equityGrantsFactory.create(
      {
        numberOfShares: 1000,
        vestedShares: 100,
        unvestedShares: 700,
        exercisedShares: 200,
        forfeitedShares: 0,
        ...overrides,
      },
      options,
    ),
};
