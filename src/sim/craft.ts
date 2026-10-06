/** Crafting recipes (survival-kit depth only — MVP non-goal list applies). */
import { invAdd, invCanAdd, invRemove, type Inventory, type ItemId } from './items';

export interface Recipe {
  id: string;
  label: string;
  in: { item: ItemId; n: number }[];
  out: { item: ItemId; n: number }[];
  hours: number; // game-hours of work
  requires?: ItemId; // e.g. knife
}

export const RECIPES: Recipe[] = [
  {
    id: 'kindling',
    label: 'Split kindling (×3)',
    in: [{ item: 'deadfall', n: 1 }],
    out: [{ item: 'kindling', n: 3 }],
    hours: 0.2,
    requires: 'knife',
  },
  {
    id: 'tinderBundle',
    label: 'Tinder bundle',
    in: [{ item: 'bark', n: 1 }, { item: 'kindling', n: 2 }],
    out: [{ item: 'tinderBundle', n: 1 }],
    hours: 0.15,
  },
  {
    id: 'barkContainer',
    label: 'Bark container',
    in: [{ item: 'bark', n: 4 }],
    out: [{ item: 'barkContainer', n: 1 }],
    hours: 0.3,
    requires: 'knife',
  },
  {
    id: 'boughBundle',
    label: 'Bough bundle (bedding)',
    in: [{ item: 'boughs', n: 6 }],
    out: [{ item: 'boughBundle', n: 1 }],
    hours: 0.25,
  },
  {
    id: 'torch',
    label: 'Torch',
    in: [{ item: 'bark', n: 2 }, { item: 'deadfall', n: 1 }],
    out: [{ item: 'torch', n: 1 }],
    hours: 0.15,
  },
];

export function canCraft(inv: Inventory, r: Recipe): boolean {
  if (r.requires && !(inv[r.requires] && inv[r.requires]! > 0)) return false;
  for (const i of r.in) if ((inv[i.item] ?? 0) < i.n) return false;
  // output must fit
  const outOk = r.out.every((o) => invCanAdd(inv, o.item, o.n));
  return outOk;
}

/** returns true on success (atomic: all-or-nothing) */
export function craft(inv: Inventory, r: Recipe): boolean {
  if (!canCraft(inv, r)) return false;
  for (const i of r.in) invRemove(inv, i.item, i.n);
  for (const o of r.out) invAdd(inv, o.item, o.n);
  return true;
}
