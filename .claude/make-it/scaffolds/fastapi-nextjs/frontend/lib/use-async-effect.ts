"use client";

import { useEffect } from "react";

/**
 * Run an async loader when the component mounts, and again whenever the
 * loader itself changes (wrap it in useCallback and list what it depends on).
 *
 * Use it for "load this page's data": `useAsyncEffect(fetchData)`.
 *
 * The loader must set state only AFTER it has awaited its request. Calling a
 * state-setting function straight from an effect is what React's
 * `react-hooks/set-state-in-effect` rule reports; awaiting it here keeps the
 * load asynchronous and visible to that rule.
 */
export function useAsyncEffect(load: () => Promise<unknown>): void {
  useEffect(() => {
    const run = async () => {
      await load();
    };
    run();
  }, [load]);
}
