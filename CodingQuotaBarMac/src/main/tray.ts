import { Tray, Menu, nativeImage } from 'electron';
import * as zlib from 'node:zlib';
import { t } from './i18n';

export type DisplayColor = 'green' | 'yellow' | 'red';

const COLORS = {
  green: '#22C55E',
  yellow: '#F59E0B',
  red: '#EF4444'
};


export interface ColorThresholds {
  green: number;
  yellow: number;
}

export interface TrayCallbacks {
  onRefresh: () => void;
  onSettings: () => void;
  onAutoStartToggle: (enabled: boolean) => void;
  onCheckUpdate: () => void;
  onQuit: () => void;
}

export function getColorByPercent(percent: number, thresholds: ColorThresholds): DisplayColor {
  if (percent >= thresholds.green) return 'green';
  if (percent >= thresholds.yellow) return 'yellow';
  return 'red';
}

// ===== PNG 编码工具 =====

const CRC_TABLE = (() => {
  const table: number[] = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
})();

function crc32(buf: Buffer): number {
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    crc = CRC_TABLE[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type: string, data: Buffer): Buffer {
  const typeBuf = Buffer.from(type, 'ascii');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const crcInput = Buffer.concat([typeBuf, data]);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(crcInput));
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

function encodePng(width: number, height: number, rgba: Buffer, isTemplate = false): Buffer {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // color type: RGBA

  const raw = Buffer.alloc(height * (1 + width * 4));
  for (let y = 0; y < height; y++) {
    raw[y * (1 + width * 4)] = 0; // filter: none
    rgba.copy(raw, y * (1 + width * 4) + 1, y * width * 4);
  }

  const compressed = zlib.deflateSync(raw);

  const chunks = [
    sig,
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', compressed),
  ];

  // macOS: 添加 sBIT chunk 标记为 template icon
  if (isTemplate) {
    const sbit = Buffer.alloc(4);
    sbit[0] = 8; // red
    sbit[1] = 8; // green
    sbit[2] = 8; // blue
    sbit[3] = 1; // alpha (1-bit = template)
    chunks.push(pngChunk('sBIT', sbit));
  }

  chunks.push(pngChunk('IEND', Buffer.alloc(0)));
  return Buffer.concat(chunks);
}

// ===== 位图字体 =====

const DIGIT_FONT: Record<string, string[]> = {
  '0': ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
  '1': ['00100', '01100', '10100', '00100', '00100', '00100', '11111'],
  '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
  '3': ['01110', '10001', '00001', '00110', '00001', '10001', '01110'],
  '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
  '5': ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
  '6': ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
  '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
  '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
  '9': ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
};

/**
 * macOS: 圆弧进度环 + 居中数字（彩色，适配深浅色菜单栏）
 */
function createMacTrayIcon(percent: number, color: DisplayColor): Electron.NativeImage {
  const size = 44;
  const cx = size / 2;
  const cy = size / 2;
  const pixels = Buffer.alloc(size * size * 4, 0);

  const hex = COLORS[color];
  const cr = parseInt(hex.slice(1, 3), 16);
  const cg = parseInt(hex.slice(3, 5), 16);
  const cb = parseInt(hex.slice(5, 7), 16);

  const outerR = 20.5;
  const innerR = 16.5;
  const midR = (outerR + innerR) / 2;
  const halfThick = (outerR - innerR) / 2;

  const rounded = Math.max(0, Math.min(100, Math.round(percent)));
  const startAngle = -Math.PI / 2;
  const sweepAngle = (rounded / 100) * Math.PI * 2;

  const setPixel = (x: number, y: number, r: number, g: number, b: number, alpha: number) => {
    if (x < 0 || x >= size || y < 0 || y >= size) return;
    const idx = (y * size + x) * 4;
    if (pixels[idx + 3] < alpha) {
      pixels[idx] = r; pixels[idx + 1] = g; pixels[idx + 2] = b; pixels[idx + 3] = alpha;
    }
  };

  // 绘制进度环（反锯齿）
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = x - cx + 0.5;
      const dy = y - cy + 0.5;
      const dist = Math.sqrt(dx * dx + dy * dy);
      const fromMid = Math.abs(dist - midR);
      if (fromMid > halfThick + 1.5) continue;

      const coverage = Math.max(0, Math.min(1, halfThick + 0.5 - fromMid));
      let normAngle = Math.atan2(dy, dx) - startAngle;
      if (normAngle < 0) normAngle += Math.PI * 2;

      const inArc = normAngle < sweepAngle;
      const alpha = inArc ? Math.round(coverage * 255) : Math.round(coverage * 50);
      setPixel(x, y, cr, cg, cb, alpha);
    }
  }

  // 绘制居中数字（2x 位图字体）
  const text = String(rounded);
  const scale = 2;
  const charGap = text.length > 2 ? 0 : 1;
  const textW = (text.length * 5 + (text.length - 1) * charGap) * scale;
  const offX = Math.floor((size - textW) / 2);
  const offY = Math.floor((size - 7 * scale) / 2);

  for (let ci = 0; ci < text.length; ci++) {
    const glyph = DIGIT_FONT[text[ci]];
    if (!glyph) continue;
    const charOffX = offX + ci * (5 + charGap) * scale;
    for (let row = 0; row < glyph.length; row++) {
      for (let col = 0; col < glyph[row].length; col++) {
        if (glyph[row][col] === '1') {
          for (let sy = 0; sy < scale; sy++)
            for (let sx = 0; sx < scale; sx++)
              setPixel(charOffX + col * scale + sx, offY + row * scale + sy, cr, cg, cb, 255);
        }
      }
    }
  }

  const pngBuffer = encodePng(size, size, pixels);
  return nativeImage.createFromBuffer(pngBuffer, { scaleFactor: 2.0 });
}

/**
 * Windows: 创建彩色图标
 */
function createWindowsTrayIcon(percent: number, color: DisplayColor): Electron.NativeImage {
  const size = 16;
  const colorHex = COLORS[color];
  const r = parseInt(colorHex.slice(1, 3), 16);
  const g = parseInt(colorHex.slice(3, 5), 16);
  const b = parseInt(colorHex.slice(5, 7), 16);

  const pixels = Buffer.alloc(size * size * 4, 0);

  const text = String(Math.round(percent));
  const charWidth = 5;
  const charHeight = 7;
  const charGap = text.length > 2 ? 0 : 1;
  const textWidth = text.length * charWidth + (text.length - 1) * charGap;
  const offsetX = Math.floor((size - textWidth) / 2);
  const offsetY = Math.floor((size - charHeight) / 2);

  for (let ci = 0; ci < text.length; ci++) {
    const glyph = DIGIT_FONT[text[ci]];
    if (!glyph) continue;
    const cx = offsetX + ci * (charWidth + charGap);
    for (let row = 0; row < glyph.length; row++) {
      for (let col = 0; col < glyph[row].length; col++) {
        if (glyph[row][col] === '1') {
          const px = cx + col;
          const py = offsetY + row;
          if (px >= 0 && px < size && py >= 0 && py < size) {
            const idx = (py * size + px) * 4;
            pixels[idx] = r;
            pixels[idx + 1] = g;
            pixels[idx + 2] = b;
            pixels[idx + 3] = 255;
          }
        }
      }
    }
  }

  const pngBuffer = encodePng(size, size, pixels);
  return nativeImage.createFromBuffer(pngBuffer);
}

/**
 * 统一入口：根据平台创建图标
 */
export function createTrayIcon(percent: number, color: DisplayColor): Electron.NativeImage {
  if (process.platform === 'darwin') {
    return createMacTrayIcon(percent, color);
  }
  return createWindowsTrayIcon(percent, color);
}

// ===== 加载动画 =====

const LOADING_FRAMES = 6;
const LOADING_INTERVAL = 180;

function createMacLoadingFrame(frameIndex: number): Electron.NativeImage {
  const size = 44;
  const cx = size / 2;
  const cy = size / 2;
  const pixels = Buffer.alloc(size * size * 4, 0);

  const outerR = 20.5;
  const innerR = 16.5;
  const midR = (outerR + innerR) / 2;
  const halfThick = (outerR - innerR) / 2;

  const gapAngle = Math.PI / 3; // 60° 缺口
  const sweepAngle = Math.PI * 2 - gapAngle;
  const startAngle = (frameIndex / LOADING_FRAMES) * Math.PI * 2 - Math.PI / 2;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = x - cx + 0.5;
      const dy = y - cy + 0.5;
      const dist = Math.sqrt(dx * dx + dy * dy);
      const fromMid = Math.abs(dist - midR);
      if (fromMid > halfThick + 1.5) continue;

      const coverage = Math.max(0, Math.min(1, halfThick + 0.5 - fromMid));
      let normAngle = Math.atan2(dy, dx) - startAngle;
      if (normAngle < 0) normAngle += Math.PI * 2;

      if (normAngle < sweepAngle) {
        const idx = (y * size + x) * 4;
        const alpha = Math.round(coverage * 255);
        if (pixels[idx + 3] < alpha) {
          pixels[idx] = 160; pixels[idx + 1] = 160; pixels[idx + 2] = 160; pixels[idx + 3] = alpha;
        }
      }
    }
  }

  const pngBuffer = encodePng(size, size, pixels);
  return nativeImage.createFromBuffer(pngBuffer, { scaleFactor: 2.0 });
}

export function createLoadingFrame(frameIndex: number): Electron.NativeImage {
  if (process.platform === 'darwin') {
    return createMacLoadingFrame(frameIndex);
  }

  // Windows fallback
  const size = 16;
  const cx = 7.5;
  const cy = 7.5;
  const radius = 5;
  const pixels = Buffer.alloc(size * size * 4, 0);
  const gapAngle = Math.PI / 3;
  const startAngle = (frameIndex / LOADING_FRAMES) * Math.PI * 2;
  const cr = 140, cg = 160, cb = 190;

  for (const r of [radius, radius - 1]) {
    for (let a = startAngle; a < startAngle + Math.PI * 2 - gapAngle; a += 0.08) {
      const x = Math.round(cx + r * Math.cos(a));
      const y = Math.round(cy + r * Math.sin(a));
      if (x >= 0 && x < size && y >= 0 && y < size) {
        const idx = (y * size + x) * 4;
        pixels[idx] = cr;
        pixels[idx + 1] = cg;
        pixels[idx + 2] = cb;
        pixels[idx + 3] = 255;
      }
    }
  }

  const pngBuffer = encodePng(size, size, pixels);
  return nativeImage.createFromBuffer(pngBuffer);
}

// ===== TrayManager =====

export class TrayManager {
  private tray: Tray | null = null;
  private currentPercent = 0;
  private currentColor: DisplayColor = 'green';
  private autoStartEnabled = false;
  private callbacks: TrayCallbacks | null = null;
  private loadingFrame = 0;
  private loadingTimer: ReturnType<typeof setInterval> | null = null;
  private storedMenu: Menu | null = null;

  constructor() {
    this.initialize();
  }

  setCallbacks(callbacks: TrayCallbacks): void {
    this.callbacks = callbacks;
  }

  private initialize(): void {
    const icon = createTrayIcon(100, 'green');
    this.tray = new Tray(icon);

    // macOS: 设置为 Template Image
    if (process.platform === 'darwin') {
      this.tray.setImage(icon);
    }

    this.setupContextMenu();
  }

  private setupContextMenu(): void {
    if (!this.tray) return;

    const contextMenu = Menu.buildFromTemplate([
      {
        label: t('tray.refresh'),
        click: () => this.handleRefresh()
      },
      {
        label: t('tray.checkUpdate'),
        click: () => this.handleCheckUpdate()
      },
      { type: 'separator' },
      {
        label: t('tray.quit'),
        click: () => this.handleQuit()
      }
    ]);

    this.storedMenu = contextMenu;

    if (process.platform === 'darwin') {
      // macOS: 不设置 setContextMenu，避免左键同时弹出 context menu
      // 右键交互由外部通过 right-click 事件处理
      this.tray.setContextMenu(null);
    } else {
      this.tray.setContextMenu(contextMenu);
    }
  }

  private handleRefresh(): void {
    this.callbacks?.onRefresh();
  }

  private handleSettings(): void {
    this.callbacks?.onSettings();
  }

  private handleAutoStartToggle(enabled: boolean): void {
    this.autoStartEnabled = enabled;
    this.callbacks?.onAutoStartToggle(enabled);
  }

  private handleCheckUpdate(): void {
    this.callbacks?.onCheckUpdate();
  }

  private handleQuit(): void {
    this.callbacks?.onQuit();
  }

  startLoading(): void {
    if (this.loadingTimer) return;
    this.loadingFrame = 0;

    const frame = createLoadingFrame(0);
    this.tray?.setImage(frame);

    this.loadingTimer = setInterval(() => {
      this.loadingFrame = (this.loadingFrame + 1) % LOADING_FRAMES;
      const frame = createLoadingFrame(this.loadingFrame);
      this.tray?.setImage(frame);
    }, LOADING_INTERVAL);
  }

  stopLoading(): void {
    if (!this.loadingTimer) return;
    clearInterval(this.loadingTimer);
    this.loadingTimer = null;

    if (this.tray) {
      const icon = createTrayIcon(this.currentPercent, this.currentColor);
      this.tray.setImage(icon);
    }
  }

  updateDisplay(percent: number, thresholds: ColorThresholds): void {
    const color = getColorByPercent(percent, thresholds);

    if (this.currentPercent === percent && this.currentColor === color) {
      return;
    }

    this.currentPercent = percent;
    this.currentColor = color;

    if (this.loadingTimer) return;

    if (this.tray) {
      const icon = createTrayIcon(percent, color);
      this.tray.setImage(icon);
    }

    // macOS: 更新 tooltip 显示百分比
    if (process.platform === 'darwin') {
      this.tray.setToolTip(`Coding Quota Bar - ${Math.round(percent)}% remaining`);
    }
  }

  setAutoStart(enabled: boolean): void {
    if (this.autoStartEnabled !== enabled) {
      this.autoStartEnabled = enabled;
      this.setupContextMenu();
    }
  }

  rebuildMenu(): void {
    this.setupContextMenu();
  }

  onClick(callback: () => void): void {
    this.tray?.on('click', callback);
  }

  onRightClick(callback: () => void): void {
    this.tray?.on('right-click', callback);
  }

  onMouseEnter(callback: () => void): void {
    this.tray?.on('mouse-enter', callback);
  }

  onMouseLeave(callback: () => void): void {
    this.tray?.on('mouse-leave', callback);
  }

  getBounds(): Electron.Rectangle | null {
    return this.tray?.getBounds() ?? null;
  }

  destroy(): void {
    if (this.loadingTimer) {
      clearInterval(this.loadingTimer);
      this.loadingTimer = null;
    }
    if (this.tray) {
      this.tray.destroy();
      this.tray = null;
    }
  }
}
