"use client";

import { type Table } from "@tanstack/react-table";
import {
  ChevronLeft,
  ChevronRight,
  ChevronsLeft,
  ChevronsRight,
} from "lucide-react";
import { cn } from "@/lib/utils";

interface DataTablePaginationProps<TData> {
  table: Table<TData>;
  enableRowSelection?: boolean;
}

export function DataTablePagination<TData>({
  table,
  enableRowSelection = false,
}: DataTablePaginationProps<TData>) {
  const pageCount = table.getPageCount();
  const pageIndex = table.getState().pagination.pageIndex;
  const pageSize = table.getState().pagination.pageSize;
  const totalRows = table.getFilteredRowModel().rows.length;

  return (
    <div className="flex flex-wrap items-center justify-between gap-4 text-sm">
      {/* Row selection count or total rows */}
      <div className="text-muted-foreground">
        {enableRowSelection ? (
          <>
            {table.getFilteredSelectedRowModel().rows.length} of {totalRows}{" "}
            row(s) selected
          </>
        ) : (
          <>{totalRows} row(s) total</>
        )}
      </div>

      <div className="flex items-center gap-4">
        {/* Page size selector */}
        <div className="flex items-center gap-2">
          <span className="text-muted-foreground">Rows per page</span>
          <select
            value={pageSize}
            onChange={(e) => table.setPageSize(Number(e.target.value))}
            className="rounded-md border border-input bg-background px-2 py-1 text-sm"
          >
            {[10, 20, 50, 100].map((size) => (
              <option key={size} value={size}>
                {size}
              </option>
            ))}
          </select>
        </div>

        {/* Page indicator */}
        <span className="text-muted-foreground">
          Page {pageIndex + 1} of {pageCount || 1}
        </span>

        {/* Navigation buttons */}
        <div className="flex items-center gap-1">
          <button
            onClick={() => table.setPageIndex(0)}
            disabled={!table.getCanPreviousPage()}
            className={cn(
              "inline-flex h-8 w-8 items-center justify-center rounded-md border border-input transition-colors",
              table.getCanPreviousPage()
                ? "hover:bg-accent hover:text-accent-foreground"
                : "opacity-50 cursor-not-allowed",
            )}
          >
            <ChevronsLeft className="h-4 w-4" />
          </button>
          <button
            onClick={() => table.previousPage()}
            disabled={!table.getCanPreviousPage()}
            className={cn(
              "inline-flex h-8 w-8 items-center justify-center rounded-md border border-input transition-colors",
              table.getCanPreviousPage()
                ? "hover:bg-accent hover:text-accent-foreground"
                : "opacity-50 cursor-not-allowed",
            )}
          >
            <ChevronLeft className="h-4 w-4" />
          </button>
          <button
            onClick={() => table.nextPage()}
            disabled={!table.getCanNextPage()}
            className={cn(
              "inline-flex h-8 w-8 items-center justify-center rounded-md border border-input transition-colors",
              table.getCanNextPage()
                ? "hover:bg-accent hover:text-accent-foreground"
                : "opacity-50 cursor-not-allowed",
            )}
          >
            <ChevronRight className="h-4 w-4" />
          </button>
          <button
            onClick={() => table.setPageIndex(pageCount - 1)}
            disabled={!table.getCanNextPage()}
            className={cn(
              "inline-flex h-8 w-8 items-center justify-center rounded-md border border-input transition-colors",
              table.getCanNextPage()
                ? "hover:bg-accent hover:text-accent-foreground"
                : "opacity-50 cursor-not-allowed",
            )}
          >
            <ChevronsRight className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
