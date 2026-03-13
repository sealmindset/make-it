"use client";

import { useState, useEffect, useCallback } from "react";
import {
  useReactTable,
  getCoreRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  getFacetedRowModel,
  getFacetedUniqueValues,
  type ColumnDef,
  type ColumnFiltersState,
  type SortingState,
  type VisibilityState,
  type PaginationState,
  type FilterFn,
  flexRender,
} from "@tanstack/react-table";
import { cn } from "@/lib/utils";
import { DataTableToolbar } from "./data-table-toolbar";
import { DataTablePagination } from "./data-table-pagination";

// Multi-select filter: checks if row value is in the selected array
const arrIncludesFilter: FilterFn<unknown> = (
  row,
  columnId,
  filterValue: string[],
) => {
  if (!filterValue || filterValue.length === 0) return true;
  const value = String(row.getValue(columnId) ?? "");
  return filterValue.includes(value);
};

interface FilterableColumn {
  id: string;
  title: string;
  options: { label: string; value: string }[];
}

interface DataTableProps<TData, TValue> {
  columns: ColumnDef<TData, TValue>[];
  data: TData[];
  /** Column ID to search globally */
  searchKey?: string;
  /** Placeholder text for global search input */
  searchPlaceholder?: string;
  /** Columns that show as toolbar filter buttons with multi-select */
  filterableColumns?: FilterableColumn[];
  /** LocalStorage key for persisting sort/filter/pagination state */
  storageKey?: string;
  /** Callback when a row is clicked */
  onRowClick?: (row: TData) => void;
}

function loadState<T>(storageKey: string, key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try {
    const stored = localStorage.getItem(`${storageKey}:${key}`);
    return stored ? JSON.parse(stored) : fallback;
  } catch {
    return fallback;
  }
}

function saveState(storageKey: string, key: string, value: unknown) {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(`${storageKey}:${key}`, JSON.stringify(value));
  } catch {
    // Ignore quota errors
  }
}

export function DataTable<TData, TValue>({
  columns,
  data,
  searchKey,
  searchPlaceholder = "Search...",
  filterableColumns = [],
  storageKey,
  onRowClick,
}: DataTableProps<TData, TValue>) {
  const sk = storageKey || "data-table";

  const [sorting, setSorting] = useState<SortingState>(() =>
    loadState(sk, "sorting", []),
  );
  const [columnFilters, setColumnFilters] = useState<ColumnFiltersState>(() =>
    loadState(sk, "columnFilters", []),
  );
  const [columnVisibility, setColumnVisibility] = useState<VisibilityState>(
    () => loadState(sk, "columnVisibility", {}),
  );
  const [pagination, setPagination] = useState<PaginationState>(() =>
    loadState(sk, "pagination", { pageIndex: 0, pageSize: 20 }),
  );

  // Persist state changes
  useEffect(() => saveState(sk, "sorting", sorting), [sk, sorting]);
  useEffect(
    () => saveState(sk, "columnFilters", columnFilters),
    [sk, columnFilters],
  );
  useEffect(
    () => saveState(sk, "columnVisibility", columnVisibility),
    [sk, columnVisibility],
  );
  useEffect(
    () => saveState(sk, "pagination", pagination),
    [sk, pagination],
  );

  const table = useReactTable({
    data,
    columns,
    filterFns: { arrIncludes: arrIncludesFilter },
    state: {
      sorting,
      columnFilters,
      columnVisibility,
      pagination,
    },
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    onColumnVisibilityChange: setColumnVisibility,
    onPaginationChange: setPagination,
    getCoreRowModel: getCoreRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFacetedRowModel: getFacetedRowModel(),
    getFacetedUniqueValues: getFacetedUniqueValues(),
  });

  return (
    <div className="space-y-4">
      <DataTableToolbar
        table={table}
        searchKey={searchKey}
        searchPlaceholder={searchPlaceholder}
        filterableColumns={filterableColumns}
      />

      {/* Table */}
      <div className="rounded-md border border-border overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            {table.getHeaderGroups().map((headerGroup) => (
              <tr key={headerGroup.id} className="border-b border-border">
                {headerGroup.headers.map((header) => (
                  <th
                    key={header.id}
                    className="h-10 px-3 text-left align-middle font-medium text-muted-foreground"
                    style={{ width: header.getSize() }}
                  >
                    {header.isPlaceholder
                      ? null
                      : flexRender(
                          header.column.columnDef.header,
                          header.getContext(),
                        )}
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.length ? (
              table.getRowModel().rows.map((row) => (
                <tr
                  key={row.id}
                  onClick={
                    onRowClick
                      ? () => onRowClick(row.original)
                      : undefined
                  }
                  className={cn(
                    "border-b border-border transition-colors hover:bg-muted/50",
                    onRowClick && "cursor-pointer",
                  )}
                >
                  {row.getVisibleCells().map((cell) => (
                    <td
                      key={cell.id}
                      className="px-3 py-2.5 align-middle"
                    >
                      {flexRender(
                        cell.column.columnDef.cell,
                        cell.getContext(),
                      )}
                    </td>
                  ))}
                </tr>
              ))
            ) : (
              <tr>
                <td
                  colSpan={columns.length}
                  className="h-24 text-center text-muted-foreground"
                >
                  No results.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <DataTablePagination table={table} />
    </div>
  );
}
