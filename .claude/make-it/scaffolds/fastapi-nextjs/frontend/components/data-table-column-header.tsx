"use client";

import { type Column } from "@tanstack/react-table";
import {
  ArrowUp,
  ArrowDown,
  ChevronsUpDown,
  Filter,
  Search,
  X,
} from "lucide-react";
import { useState, useRef, useEffect } from "react";
import { cn } from "@/lib/utils";

interface DataTableColumnHeaderProps<TData, TValue> {
  column: Column<TData, TValue>;
  title: string;
  className?: string;
}

export function DataTableColumnHeader<TData, TValue>({
  column,
  title,
  className,
}: DataTableColumnHeaderProps<TData, TValue>) {
  const [showFilter, setShowFilter] = useState(false);
  const filterRef = useRef<HTMLDivElement>(null);

  // Close filter dropdown on outside click
  useEffect(() => {
    if (!showFilter) return;
    const handler = (e: MouseEvent) => {
      if (filterRef.current && !filterRef.current.contains(e.target as Node)) {
        setShowFilter(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [showFilter]);

  if (!column.getCanSort() && !column.getCanFilter()) {
    return <div className={className}>{title}</div>;
  }

  const sorted = column.getIsSorted();
  const isFiltered = column.getIsFiltered();

  return (
    <div className={cn("relative flex items-center gap-1", className)}>
      {/* Sort toggle */}
      {column.getCanSort() ? (
        <button
          onClick={() => column.toggleSorting()}
          className="-ml-1 flex items-center gap-1 rounded px-1 py-0.5 transition-colors hover:bg-accent"
        >
          <span className="select-none">{title}</span>
          {sorted === "asc" ? (
            <ArrowUp className="h-3.5 w-3.5" />
          ) : sorted === "desc" ? (
            <ArrowDown className="h-3.5 w-3.5" />
          ) : (
            <ChevronsUpDown className="h-3.5 w-3.5 text-muted-foreground/50" />
          )}
        </button>
      ) : (
        <span>{title}</span>
      )}

      {/* Filter trigger */}
      {column.getCanFilter() && (
        <button
          onClick={() => setShowFilter(!showFilter)}
          className={cn(
            "rounded p-0.5 transition-colors hover:bg-accent",
            isFiltered && "text-primary",
          )}
          title={`Filter ${title}`}
        >
          <Filter
            className={cn("h-3 w-3", isFiltered ? "fill-primary/20" : "")}
          />
        </button>
      )}

      {/* Excel-like filter dropdown */}
      {showFilter && column.getCanFilter() && (
        <div
          ref={filterRef}
          className="absolute left-0 top-full z-40 mt-1 w-60 rounded-md border border-border bg-card p-3 shadow-lg"
        >
          <ExcelColumnFilter column={column} title={title} />
        </div>
      )}
    </div>
  );
}

/**
 * Excel-like column filter popup:
 * - Search box to filter the value list
 * - Select All / Clear All buttons
 * - Scrollable list of checkboxes with unique values
 * - Count indicator
 */
function ExcelColumnFilter<TData, TValue>({
  column,
  title,
}: {
  column: Column<TData, TValue>;
  title: string;
}) {
  const [search, setSearch] = useState("");
  const filterValue = column.getFilterValue();

  // Get unique values from the faceted model
  const facetedValues = column.getFacetedUniqueValues();
  const allValues = Array.from(facetedValues.keys())
    .map(String)
    .filter(Boolean)
    .sort();

  // Filter the value list by search term
  const filteredValues = search
    ? allValues.filter((v) => v.toLowerCase().includes(search.toLowerCase()))
    : allValues;

  // Current selection (array of selected values)
  const selected: string[] = Array.isArray(filterValue) ? filterValue : [];
  const isActive = selected.length > 0;

  const toggleValue = (value: string) => {
    const next = selected.includes(value)
      ? selected.filter((v) => v !== value)
      : [...selected, value];
    column.setFilterValue(next.length > 0 ? next : undefined);
  };

  const selectAll = () => {
    column.setFilterValue(
      filteredValues.length > 0 ? [...filteredValues] : undefined,
    );
  };

  const clearAll = () => {
    column.setFilterValue(undefined);
  };

  return (
    <div className="space-y-2">
      <p className="text-xs font-medium text-muted-foreground">
        Filter: {title}
      </p>

      {/* Search box */}
      <div className="relative">
        <Search className="absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
        <input
          type="text"
          placeholder="Search values..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full rounded-md border border-input bg-background py-1 pl-7 pr-2 text-xs outline-none placeholder:text-muted-foreground focus-visible:ring-1 focus-visible:ring-ring"
        />
      </div>

      {/* Select All / Clear All */}
      <div className="flex items-center justify-between">
        <button
          onClick={selectAll}
          className="text-xs text-primary hover:underline"
        >
          Select all ({filteredValues.length})
        </button>
        {isActive && (
          <button
            onClick={clearAll}
            className="inline-flex items-center gap-0.5 text-xs text-muted-foreground hover:text-foreground"
          >
            <X className="h-3 w-3" />
            Clear
          </button>
        )}
      </div>

      {/* Checkbox list */}
      <div className="max-h-48 space-y-0.5 overflow-y-auto">
        {filteredValues.length === 0 ? (
          <p className="py-2 text-center text-xs text-muted-foreground">
            No values found
          </p>
        ) : (
          filteredValues.map((value) => {
            const count = facetedValues.get(value) ?? 0;
            const checked = selected.includes(value);
            return (
              <label
                key={value}
                className="flex cursor-pointer items-center gap-2 rounded px-1 py-1 text-xs hover:bg-accent/50"
              >
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() => toggleValue(value)}
                  className="rounded border-border"
                />
                <span className="flex-1 truncate">{value}</span>
                <span className="text-muted-foreground">{count}</span>
              </label>
            );
          })
        )}
      </div>

      {/* Active filter indicator */}
      {isActive && (
        <p className="text-xs text-primary">
          {selected.length} of {allValues.length} selected
        </p>
      )}
    </div>
  );
}
