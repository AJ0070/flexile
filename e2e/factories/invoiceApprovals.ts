import { db } from "@test/db";
import { companyAdministratorsFactory } from "@test/factories/companyAdministrators";
import { invoicesFactory } from "@test/factories/invoices";
import { eq, sql } from "drizzle-orm";
import { invoiceApprovals, invoices, users } from "@/db/schema";
import { assert } from "@/utils/assert";

export const invoiceApprovalsFactory = {
  create: async (overrides: Partial<typeof invoiceApprovals.$inferInsert> = {}) => {
    const invoice = overrides.invoiceId
      ? await db.query.invoices.findFirst({
          where: eq(invoices.id, overrides.invoiceId),
        })
      : (await invoicesFactory.create()).invoice;
    assert(invoice !== undefined);

    let approverId = overrides.approverId;
    if (!approverId) {
      const companyAdministrator = await companyAdministratorsFactory.create({
        companyId: invoice.companyId,
      });
      const adminUser = await db.query.users.findFirst({
        where: eq(users.id, companyAdministrator.administrator.userId),
      });
      assert(adminUser !== undefined);
      approverId = adminUser.id;
    }

    const approvedAt = overrides.approvedAt ?? new Date();

    const [approval] = await db
      .insert(invoiceApprovals)
      .values({
        invoiceId: invoice.id,
        approverId,
        approvedAt,
        ...overrides,
      })
      .returning();

    await db
      .update(invoices)
      .set({
        invoiceApprovalsCount: sql`${invoices.invoiceApprovalsCount} + 1`,
      })
      .where(eq(invoices.id, invoice.id));

    return { approval };
  },
};
