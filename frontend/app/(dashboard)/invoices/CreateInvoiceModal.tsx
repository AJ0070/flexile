"use client";

import { ArrowUpTrayIcon, PlusIcon } from "@heroicons/react/16/solid";
import { type DateValue, getLocalTimeZone, parseDate, today } from "@internationalized/date";
import { useMutation } from "@tanstack/react-query";
import { List } from "immutable";
import React, { useCallback, useMemo, useRef, useState } from "react";
import DatePicker from "@/components/DatePicker";
import NumberInput from "@/components/NumberInput";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import { useCurrentCompany, useCurrentUser } from "@/global";
import { request } from "@/utils/request";
import { company_invoices_path, parse_pdf_company_invoices_path } from "@/utils/routes";

// Minimal line item type for quick form
type QuickLineItem = {
  description: string;
  quantity: string; // minutes or qty as string
  hourly: boolean;
  pay_rate_in_subunits: number; // cents
  errors?: string[] | null;
};

export default function CreateInvoiceModal({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  onCreated?: () => void;
}) {
  const company = useCurrentCompany();
  const user = useCurrentUser();

  const defaultRate = user.roles.worker?.payRateInSubunits ?? 0;

  const [invoiceNumber, setInvoiceNumber] = useState("");
  const [issueDate, setIssueDate] = useState<DateValue>(() => today(getLocalTimeZone()));
  const [notes, setNotes] = useState("");
  const isProjectBased = user.roles.worker?.payRateType === "project_based";
  const [lineItems, setLineItems] = useState(
    List<QuickLineItem>([
      {
        description: "",
        quantity: (isProjectBased ? 1 : 60).toString(),
        hourly: !isProjectBased,
        pay_rate_in_subunits: defaultRate,
      },
    ]),
  );

  const uploadRef = useRef<HTMLInputElement>(null);
  const [droppedFile, setDroppedFile] = useState<File | null>(null);
  const [parsing, setParsing] = useState(false);
  const [parseError, setParseError] = useState<string | null>(null);

  const parseQuantity = (value: string | null | undefined) => {
    const parsed = value ? Number.parseFloat(value) : NaN;
    return Number.isNaN(parsed) ? 0 : parsed;
  };

  const addLineItem = () =>
    setLineItems((items) =>
      items.push({
        description: "",
        quantity: (isProjectBased ? 1 : 60).toString(),
        hourly: !isProjectBased,
        pay_rate_in_subunits: defaultRate,
      }),
    );

  const updateLineItem = (index: number, update: Partial<QuickLineItem>) =>
    setLineItems((items) =>
      items.update(index, (li: QuickLineItem) => {
        const next: QuickLineItem = { ...li, ...update };
        next.errors = [];
        if (!next.description?.length) next.errors.push("description");
        if (!next.quantity || parseQuantity(next.quantity) <= 0) next.errors.push("quantity");
        return next;
      }),
    );

  const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null;

  const prefillFromParse = async (file: File) => {
    setParsing(true);
    setParseError(null);
    try {
      const form = new FormData();
      form.append("file", file);
      const res = await request({
        method: "POST",
        url: parse_pdf_company_invoices_path(company.id),
        accept: "json",
        formData: form,
        assertOk: true,
      });
      const data = await res.json();
      if (data.invoiceNumber && !invoiceNumber) setInvoiceNumber(String(data.invoiceNumber));
      if (data.invoiceDate) {
        try {
          setIssueDate(parseDate(String(data.invoiceDate)));
        } catch {
          // ignore invalid date
        }
      }
      if (data.notes && !notes) setNotes(String(data.notes));
      if (Array.isArray(data.lineItems) && data.lineItems.length) {
        const mapped = data.lineItems.map((raw: unknown) => {
          const obj = isRecord(raw) ? raw : {};
          const description = typeof obj.description === "string" ? obj.description : "";
          const q = obj.quantity;
          const quantity = typeof q === "number" || typeof q === "string" ? String(q) : "";
          const hourly = obj.hourly === true;
          const prs = obj.pay_rate_in_subunits;
          const pay_rate_in_subunits = typeof prs === "number" ? prs : Number(prs ?? 0);
          const line: QuickLineItem = { description, quantity, hourly, pay_rate_in_subunits };
          return line;
        });
        setLineItems(List<QuickLineItem>(mapped));
      }
    } catch (_err) {
      setParseError("Could not parse PDF. You can still submit manually.");
    } finally {
      setParsing(false);
    }
  };

  const onDrop = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    const file = e.dataTransfer.files?.[0];
    if (!file) return;
    setDroppedFile(file);
    void prefillFromParse(file);
  }, []);

  const submit = useMutation({
    mutationFn: async () => {
      const formData = new FormData();
      formData.append("invoice[invoice_number]", invoiceNumber.trim());
      formData.append("invoice[invoice_date]", issueDate.toString());
      for (const li of lineItems) {
        if (!li.description || !li.quantity) continue;
        formData.append("invoice_line_items[][description]", li.description);
        formData.append("invoice_line_items[][quantity]", li.quantity.toString());
        formData.append("invoice_line_items[][hourly]", li.hourly.toString());
        formData.append("invoice_line_items[][pay_rate_in_subunits]", li.pay_rate_in_subunits.toString());
      }
      if (notes.length) formData.append("invoice[notes]", notes);
      // Optional: attach dropped PDF as an expense receipt with zero amount so review can adjust
      if (droppedFile) {
        formData.append("invoice_expenses[][description]", droppedFile.name);
        formData.append("invoice_expenses[][expense_category_id]", String(0));
        formData.append("invoice_expenses[][total_amount_in_cents]", String(0));
        formData.append("invoice_expenses[][attachment]", droppedFile);
      }

      await request({
        method: "POST",
        url: company_invoices_path(company.id),
        accept: "json",
        formData,
        assertOk: true,
      });
    },
    onSuccess: () => {
      onOpenChange(false);
      onCreated?.();
      // Let the caller invalidate queries; page.tsx already does that on list
    },
  });

  const canSubmit = useMemo(() => {
    const hasValidLine = lineItems.some((li) => Boolean(li.description) && parseQuantity(li.quantity) > 0);
    return invoiceNumber.trim().length > 0 && hasValidLine && !submit.isPending;
  }, [invoiceNumber, lineItems, submit.isPending]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="md:w-[760px]">
        <DialogHeader>
          <DialogTitle>New invoice</DialogTitle>
          <DialogDescription>Quickly create an invoice. Drag and drop a PDF to prefill basics.</DialogDescription>
        </DialogHeader>

        <div className="grid gap-4">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
            <div className="flex flex-col gap-2">
              <Label htmlFor="invoice-id">Invoice ID</Label>
              <Input id="invoice-id" value={invoiceNumber} onChange={(e) => setInvoiceNumber(e.target.value)} />
            </div>
            <div className="flex flex-col gap-2 md:col-span-1">
              <DatePicker
                value={issueDate}
                onChange={(date) => date && setIssueDate(date)}
                label="Invoice date"
                granularity="day"
              />
            </div>
            <div className="flex flex-col gap-2 md:col-span-1">
              <Label className="sr-only">Upload</Label>
              <div
                onDragOver={(e) => e.preventDefault()}
                onDrop={onDrop}
                className="flex items-center justify-between gap-2 rounded-md border border-dashed p-3 text-sm"
                role="button"
                aria-label="Drag and drop PDF"
              >
                <div className="truncate">
                  {parsing ? "Parsing PDF..." : droppedFile ? droppedFile.name : "Drag & drop PDF (optional)"}
                </div>
                <Button variant="outline" size="small" onClick={() => uploadRef.current?.click()}>
                  <ArrowUpTrayIcon className="size-4" />
                  Upload
                </Button>
                <input
                  ref={uploadRef}
                  type="file"
                  accept="application/pdf"
                  className="hidden"
                  onChange={(e) => {
                    const f = e.target.files?.[0] || null;
                    if (f) {
                      setDroppedFile(f);
                      void prefillFromParse(f);
                    }
                  }}
                />
              </div>
              {parseError ? <div className="mt-1 text-xs text-red-600">{parseError}</div> : null}
            </div>
          </div>

          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[55%]">Line item</TableHead>
                <TableHead>Hours / Qty</TableHead>
                <TableHead>Rate</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {lineItems.toArray().map((item, idx) => (
                <TableRow key={idx}>
                  <TableCell>
                    <Input
                      value={item.description}
                      placeholder="Description"
                      aria-invalid={item.errors?.includes("description")}
                      onChange={(e) => updateLineItem(idx, { description: e.target.value })}
                    />
                  </TableCell>
                  <TableCell>
                    <Input
                      inputMode="decimal"
                      value={item.quantity}
                      aria-label="Hours / Qty"
                      aria-invalid={item.errors?.includes("quantity")}
                      onChange={(e) => updateLineItem(idx, { quantity: e.target.value })}
                    />
                  </TableCell>
                  <TableCell>
                    <NumberInput
                      value={item.pay_rate_in_subunits / 100}
                      onChange={(value: number | null) =>
                        updateLineItem(idx, { pay_rate_in_subunits: (value ?? 0) * 100 })
                      }
                      aria-label="Rate"
                      placeholder="0"
                      prefix="$"
                      decimal
                    />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <div>
            <Button variant="link" onClick={addLineItem}>
              <PlusIcon className="inline size-4" /> Add line item
            </Button>
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="notes">Notes</Label>
            <Textarea id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={submit.isPending}>
            Cancel
          </Button>
          <Button variant="primary" onClick={() => canSubmit && submit.mutate()} disabled={!canSubmit}>
            {submit.isPending ? "Creating..." : "Create invoice"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
