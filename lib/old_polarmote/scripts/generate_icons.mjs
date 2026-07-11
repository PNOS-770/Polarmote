import sharp from 'sharp';
import fs from 'fs';

const svgPath = 'assets/images/app_icon.svg';
const svg = fs.readFileSync(svgPath);

async function gen(size, outPath) {
  const dir = outPath.substring(0, outPath.lastIndexOf('/'));
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const png = await sharp(svg).resize(size, size).png().toBuffer();
  fs.writeFileSync(outPath, png);
  console.log(`  ${size}x${size} -> ${outPath}`);
}

function px(size, scale) {
  return Math.round(size * scale);
}

// === macOS ===
console.log('macOS...');
await gen(16,  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png');
await gen(32,  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png');
await gen(64,  'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png');
await gen(128, 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png');
await gen(256, 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png');
await gen(512, 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png');
await gen(1024,'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png');

// === iOS ===
console.log('iOS...');
await gen(px(20,2), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png');
await gen(px(20,3), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png');
await gen(px(29,1), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png');
await gen(px(29,2), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png');
await gen(px(29,3), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png');
await gen(px(40,2), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png');
await gen(px(40,3), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png');
await gen(px(60,2), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png');
await gen(px(60,3), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png');
await gen(px(20,1), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png');
await gen(px(40,1), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png');
await gen(px(76,1), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png');
await gen(px(76,2), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png');
await gen(Math.round(px(83.5,2)), 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png');
await gen(1024,     'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png');

// === Android ===
console.log('Android...');
await gen(48,  'android/app/src/main/res/mipmap-mdpi/ic_launcher.png');
await gen(72,  'android/app/src/main/res/mipmap-hdpi/ic_launcher.png');
await gen(96,  'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png');
await gen(144, 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png');
await gen(192, 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png');

await gen(48,  'android/app/src/main/res/drawable-mdpi/splash_icon.png');
await gen(72,  'android/app/src/main/res/drawable-hdpi/splash_icon.png');
await gen(96,  'android/app/src/main/res/drawable-xhdpi/splash_icon.png');
await gen(144, 'android/app/src/main/res/drawable-xxhdpi/splash_icon.png');
await gen(192, 'android/app/src/main/res/drawable-xxxhdpi/splash_icon.png');

// === Web ===
console.log('Web...');
await gen(32,  'web/favicon.png');
await gen(192, 'web/icons/Icon-192.png');
await gen(512, 'web/icons/Icon-512.png');
await gen(192, 'web/icons/Icon-maskable-192.png');
await gen(512, 'web/icons/Icon-maskable-512.png');

// === Assets ===
console.log('Assets...');
await gen(128, 'assets/images/app_icon_128.png');

// === Windows ICO ===
console.log('Windows ICO...');
const icoSizes = [16, 24, 32, 40, 48, 64, 128, 256];
const icoData = [];
for (const size of icoSizes) {
  icoData.push(await sharp(svg).resize(size, size).png().toBuffer());
}
const dirEntrySize = 16;
const offset = 6 + icoSizes.length * dirEntrySize;
let curOff = offset;
const entries = [];
for (let i = 0; i < icoSizes.length; i++) {
  const sz = icoSizes[i];
  const w = sz === 256 ? 0 : sz;
  const h = sz === 256 ? 0 : sz;
  const buf = Buffer.alloc(dirEntrySize);
  buf.writeUInt8(w, 0);
  buf.writeUInt8(h, 1);
  buf.writeUInt8(0, 2);
  buf.writeUInt8(0, 3);
  buf.writeUInt16LE(1, 4);
  buf.writeUInt16LE(32, 6);
  buf.writeUInt32LE(icoData[i].length, 8);
  buf.writeUInt32LE(curOff, 12);
  entries.push(buf);
  curOff += icoData[i].length;
}
const header = Buffer.alloc(6);
header.writeUInt16LE(0, 0);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(icoSizes.length, 4);
const icoBuf = Buffer.concat([header, ...entries, ...icoData]);
fs.writeFileSync('windows/runner/resources/app_icon.ico', icoBuf);
console.log('  ICO done');

console.log('All icons regenerated');
