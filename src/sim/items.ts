/** Items + inventory (MVP set per docs/DESIGN-world.md). */

export type ItemId =
  | 'deadfall' // raw standing-dead wood
  | 'kindling' // split/processed small wood
  | 'bark' // birch bark strips
  | 'boughs' // spruce boughs
  | 'rock' // hand-carriable stone
  | 'snow' // packed snow (needs container; melt before drinking)
  | 'waterRaw' // untreated water in container
  | 'waterClean' // boiled water
  | 'tinderBundle' // bark+kindling, catches an ember
  | 'barkContainer' // carries snow/water
  | 'torch'
  | 'boughBundle' // 6 boughs — bedding/shelter insulation unit
  | 'knife'
  | 'tinCup'
  | 'blanket' // emergency blanket
  | 'flareGun'
  | 'flare'
  | 'ductTape'
  | 'berries'
  | 'meat'
  | 'meatCooked'
  | 'cordage';

export interface ItemDef {
  id: ItemId;
  label: string;
  stack: number; // max stack
  weight: number; // kg per unit
  key: boolean; // never dropped
}

export const ITEMS: Record<ItemId, ItemDef> = {
  deadfall: { id: 'deadfall', label: 'Deadfall wood', stack: 6, weight: 1.2, key: false },
  kindling: { id: 'kindling', label: 'Kindling', stack: 12, weight: 0.3, key: false },
  bark: { id: 'bark', label: 'Birch bark', stack: 10, weight: 0.2, key: false },
  boughs: { id: 'boughs', label: 'Spruce boughs', stack: 12, weight: 0.4, key: false },
  rock: { id: 'rock', label: 'Rock', stack: 3, weight: 2.5, key: false },
  snow: { id: 'snow', label: 'Packed snow', stack: 2, weight: 0.5, key: false },
  waterRaw: { id: 'waterRaw', label: 'Water (raw)', stack: 2, weight: 1, key: false },
  waterClean: { id: 'waterClean', label: 'Water (boiled)', stack: 2, weight: 1, key: false },
  tinderBundle: { id: 'tinderBundle', label: 'Tinder bundle', stack: 4, weight: 0.3, key: false },
  barkContainer: { id: 'barkContainer', label: 'Bark container', stack: 2, weight: 0.4, key: false },
  torch: { id: 'torch', label: 'Torch', stack: 2, weight: 0.6, key: false },
  boughBundle: { id: 'boughBundle', label: 'Bough bundle', stack: 4, weight: 2, key: false },
  knife: { id: 'knife', label: 'Knife', stack: 1, weight: 0.2, key: true },
  tinCup: { id: 'tinCup', label: 'Tin cup', stack: 1, weight: 0.2, key: true },
  blanket: { id: 'blanket', label: 'Emergency blanket', stack: 1, weight: 0.15, key: true },
  flareGun: { id: 'flareGun', label: 'Flare gun', stack: 1, weight: 0.8, key: true },
  flare: { id: 'flare', label: 'Flare', stack: 2, weight: 0.15, key: true },
  ductTape: { id: 'ductTape', label: 'Duct tape', stack: 2, weight: 0.25, key: false },
  berries: { id: 'berries', label: 'Berries', stack: 8, weight: 0.15, key: false },
  meat: { id: 'meat', label: 'Small game (raw)', stack: 4, weight: 0.8, key: false },
  meatCooked: { id: 'meatCooked', label: 'Cooked meat', stack: 4, weight: 0.6, key: false },
  cordage: { id: 'cordage', label: 'Cordage', stack: 4, weight: 0.2, key: false },
};

export type Inventory = Partial<Record<ItemId, number>>;

export const CARRY_LIMIT_KG = 18;

export function invWeight(inv: Inventory): number {
  let w = 0;
  for (const [id, n] of Object.entries(inv)) w += (n ?? 0) * ITEMS[id as ItemId].weight;
  return w;
}

export function invAdd(inv: Inventory, id: ItemId, n = 1): number {
  const cur = inv[id] ?? 0;
  let room = Math.min(ITEMS[id].stack - cur, n);
  // respect the carry limit
  const kgRoom = CARRY_LIMIT_KG - invWeight(inv);
  const byWeight = Math.floor(kgRoom / ITEMS[id].weight);
  room = Math.min(room, Math.max(0, byWeight));
  const added = Math.max(0, room);
  if (added > 0) inv[id] = cur + added;
  return added; // remainder not added
}

export function invRemove(inv: Inventory, id: ItemId, n = 1): boolean {
  const cur = inv[id] ?? 0;
  if (cur < n) return false;
  if (cur === n) delete inv[id];
  else inv[id] = cur - n;
  return true;
}

export function invHas(inv: Inventory, id: ItemId, n = 1): boolean {
  return (inv[id] ?? 0) >= n;
}

export function invCanAdd(inv: Inventory, id: ItemId, n = 1, extraKg = 0): boolean {
  const room = ITEMS[id].stack - (inv[id] ?? 0);
  return room >= n && invWeight(inv) + n * ITEMS[id].weight + extraKg <= CARRY_LIMIT_KG;
}
