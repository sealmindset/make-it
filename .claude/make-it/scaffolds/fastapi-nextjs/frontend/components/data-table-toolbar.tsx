"use client";

import { type Table } from "@tanstack/react-table";
import { Search, X, Filter, ChevronDown, Eye } from "lucide-react";
import { useState, useRef, useEffect } from "react";
import { cn } from "@/lib/utils";

interface FilterableColumn {
  id: string;
  title: string;
  options: { label: string; value: string }[];
}

interface DataTableToolbarProps<TData> {
  table: Table<TData>;
  searchKey?: string;
  searchPlaceholder?: string;
  filterableColumns?: FilterableColumn[];
}

export function DataTableToolbar<TData>({
  table,
  searchKey,
  searchPlaceholder = "Search...",
  filterableColumns = [],
}: DataTableToolbarProps<TData>) {
  const activeFilterCount = table.getState().columnFilters.length;
  const searchValue = searchKey
    ? (table.getColumn(searchKey)?.getFilterValue() as string) ?? ""
    : "";

  const isFiltered =
    activeFilterCount > 0 || (searchKey && searchValue.length > 0);

  return (
    <div className="flex flex-wrap items-center gap-2">
      {/* Global search on a specific column */}
      {searchKey && (
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            placeholder={searchPlaceholder}
            value={searchValue}
            onChange={(e) =>
              table.getColumn(searchKey)?.setFilterValue(e.target.value)
            }
            className="w-full rounded-md border border-input bg-background py-1.5 pl-8 pr-3 text-sm outline-none ring-offset-background placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
          />
        </div>
      )}

      {/* Faceted filter buttons (one per filterable column) */}
      {filterableColumns.map((fc) => {
        const column = table.getColumn(fc.id);
        if (!column) return null;
        return (
          <FacetedFilterButton
            key={fc.id}
            column={column}
            title={fc.title}
            options={fc.options}
          />
        );
      })}

      {/* Active filter count badge */}
      {activeFilterCount > 0 && (
        <span className="inline-flex items-center rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-medium text-primary">
          {activeFilterCount} filter{activeFilterCount !== 1 ? "s" : ""}
        </span>
      )}

      {/* Reset all filters */}
      {isFiltered && (
        <button
          onClick={() => {
            table.resetColumnFilters();
          }}
          className="inline-flex items-center gap-1 rounded-md border border-input bg-background px-2.5 py-1 text-xs text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground"
        >
          <X className="h-3 w-3" />
          Reset
        </button>
      )}

      {/* Spacer */}
      <div className="flex-1" />

      {/* Column visibility */}
      <ColumnVisibilityDropdown table={table} />
    </div>
  );
}

/**
 * Faceted filter button: click to open a popover with multi-select checkboxes.
 * Shows badge with count of selected values.
 */
function FacetedFilterButton<TData>({
  column,
  title,
  options,
}: {
  column: ReturnType<Table<TData>["getColumn"]>;
  title: string;
  options: { label: string; value: string }[];
}) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const ref = useRef<HTMLDivElement>(null);

  if (!column) return null;

  const filterValue = column.getFilterValue();
  const selected: string[] = Array.isArray(filterValue) ? filterValue : [];

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  const filteredOptions = search
    ? options.filter((o) =>
        o.label.toLowerCase().includes(search.toLowerCase()),
      )
    : options;

  const toggleValue = (value: string) => {
    const next = selected.includes(value)
      ? selected.filter((v) => v !== value)
      : [...selected, value];
    column.setFilterValue(next.length > 0 ? next : undefined);
  };

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => {
          setOpen(!open);
          setSearch("");
        }}
        className={cn(
          "inline-flex h-8 items-center gap-1.5 rounded-md border px-2.5 text-xs transition-colors",
          selected.length > 0
            ? "border-primary/50 bg-primary/5 text-primary"
            : "border-input bg-background text-muted-foreground hover:bg-accent hover:text-accent-foreground",
        )}
      >
        <Filter className="h-3.5 w-3.5" />
        {title}
        {selected.length > 0 && (
          <span className="ml-1 inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-primary px-1 text-[10px] font-medium text-primary-foreground">
            {selected.length}
          </span>
        )}
        <ChevronDown className="h-3 w-3" />
      </button>

      {open && (
        <div className="absolute left-0 top-full z-40 mt-1 w-56 rounded-md border border-border bg-card p-2 shadow-lg">
          {/* Search */}
          <div className="relative mb-2">
            <Search className="absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
            <input
              type="text"
              placeholder={`Search ${title.toLowerCase()}...`}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full rounded-md border border-input bg-background py-1 pl-7 pr-2 text-xs outline-none placeholder:text-muted-foreground focus-visible:ring-1 focus-visible:ring-ring"
              autoFocus
            />
          </div>

          {/* Select All / Clear */}
          <div className="mb-1 flex items-center justify-between px-1">
            <button
              onClick={() => {
                const allValues = filteredOptions.map((o) => o.value);
                column.setFilterValue(allValues.length > 0 ? allValues : undefined);
              }}
              className="text-[10px] text-primary hover:underline"
            >
              Select all
            </button>
            {selected.length > 0 && (
              <button
                onClick={() => column.setFilterValue(undefined)}
                className="text-[10px] text-muted-foreground hover:text-foreground"
              >
                Clear
              </button>
            )}
          </div>

          {/* Options */}
          <div className="max-h-48 space-y-0.5 overflow-y-auto">
            {filteredOptions.length === 0 ? (
              <p className="py-2 text-center text-xs text-muted-foreground">
                No options
              </p>
            ) : (
              filteredOptions.map((option) => {
                const checked = selected.includes(option.value);
                return (
                  <label
                    key={option.value}
                    className="flex cursor-pointer items-center gap-2 rounded px-1 py-1 text-xs hover:bg-accent/50"
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={() => toggleValue(option.value)}
                      className="rounded border-border"
                    />
                    <span className="truncate">{option.label}</span>
                  </label>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * Column visibility dropdown.
 */
function ColumnVisibilityDropdown<TData>({ table }: { table: Table<TData> }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen(!open)}
        className="inline-flex h-8 items-center gap-1.5 rounded-md border border-input bg-background px-2.5 text-xs text-muted-foreground transition-colors hover:bg-accent hover:text-accent-foreground"
      >
        <Eye className="h-3.5 w-3.5" />
        Columns
      </button>

      {open && (
        <div className="absolute right-0 top-full z-30 mt-1 w-48 rounded-md border border-border bg-card p-2 shadow-lg">
          <p className="mb-1 px-1 text-xs font-medium text-muted-foreground">
            Toggle columns
          </p>
          {table.getAllLeafColumns().map((column) => {
            if (!column.getCanHide()) return null;
            return (
              <label
                key={column.id}
                className="flex items-center gap-2 rounded px-1 py-1 text-xs hover:bg-accent/50"
              >
                <input
                  type="checkbox"
                  checked={column.getIsVisible()}
                  onChange={column.getToggleVisibilityHandler()}
                  className="rounded border-border"
                />
                <span className="truncate capitalize">
                  {typeof column.columnDef.header === "string"
                    ? column.columnDef.header
                    : column.id.replace(/_/g, " ")}
                </span>
              </label>
            );
          })}
        </div>
      )}
    </div>
  );
}
