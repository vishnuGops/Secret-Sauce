import { detectBrands, isCopycat } from './brands.mjs';

const cases = [
  'Homemade Chocolate Chip Cookies',
  'Copycat Olive Garden Zuppa Toscana',
  'Subway Italian BMT copycat',
  'Better Than Takeout Fried Rice',
  'Chipotle mayo dressing',
  'Copycat Chipotle Barbacoa',
  'Starbucks Pumpkin Spice Latte',
  'Restaurant Style Salsa',
];

for (const t of cases) {
  console.log(
    (isCopycat(t) ? 'COPYCAT' : 'plain  ') + '  ' +
    JSON.stringify(detectBrands(t)).padEnd(46) + '| ' + t,
  );
}
