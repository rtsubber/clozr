/**
 * Clozr Fingerprint Helper — Free Tier Enforcement
 *
 * Collects browser fingerprint, registers with Local-Eye,
 * and checks if this device has exceeded the free meeting limit.
 *
 * Usage from Flutter web JS interop:
 *   window.clozrFingerprint.send()
 *   window.clozrFingerprint.check()
 *   window.clozrFingerprint.sendAndCheck()
 */
const LOCALEYE_FP_API = 'https://localeye.co';
const CLOZR_API = window.location.origin;

const ClozrFP = {
  _components: null,
  _hash: null,

  async collect() {
    if (this._components) return this._components;

    const c = {};
    c.screen_width = screen.width;
    c.screen_height = screen.height;
    c.color_depth = screen.colorDepth;
    c.pixel_ratio = window.devicePixelRatio;
    c.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    c.timezone_offset = new Date().getTimezoneOffset();
    c.language = navigator.language;
    c.languages = (navigator.languages || []).join(',');
    c.platform = navigator.platform || 'unknown';
    c.hardware_concurrency = navigator.hardwareConcurrency || 0;
    c.max_touch_points = navigator.maxTouchPoints || 0;
    c.device_memory = navigator.deviceMemory || 0;

    // Canvas fingerprint
    try {
      const canvas = document.createElement('canvas');
      canvas.width = 200; canvas.height = 50;
      const ctx = canvas.getContext('2d');
      ctx.textBaseline = 'top';
      ctx.font = '14px Arial';
      ctx.fillStyle = '#f60';
      ctx.fillRect(50, 0, 100, 50);
      ctx.fillStyle = '#069';
      ctx.fillText('Clozr ✅', 2, 15);
      ctx.fillStyle = 'rgba(102,204,0,0.7)';
      ctx.fillText('Clozr ✅', 4, 17);
      c.canvas_hash = await this._hash(canvas.toDataURL());
    } catch (e) { c.canvas_hash = 'error'; }

    // WebGL renderer
    try {
      const gl = document.createElement('canvas').getContext('webgl');
      const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
      c.webgl_vendor = debugInfo ? gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL) : 'unknown';
      c.webgl_renderer = debugInfo ? gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL) : 'unknown';
    } catch (e) { c.webgl_vendor = 'unknown'; c.webgl_renderer = 'unknown'; }

    // Font probing
    const testFonts = ['Arial','Helvetica','Times New Roman','Courier','Georgia',
      'Verdana','Comic Sans MS','Impact','Trebuchet MS','Segoe UI','Roboto'];
    const available = [];
    const span = document.createElement('span');
    span.style.fontSize = '72px'; span.innerHTML = 'mmmmmmmmmmlli';
    document.body.appendChild(span);
    const defaultWidth = span.offsetWidth;
    for (const font of testFonts) {
      span.style.fontFamily = font;
      if (span.offsetWidth !== defaultWidth) available.push(font);
    }
    document.body.removeChild(span);
    c.fonts = available.sort().join(',');

    // Plugins
    const plugins = [];
    for (let i = 0; i < navigator.plugins.length; i++) plugins.push(navigator.plugins[i].name);
    c.plugins = plugins.sort().join(',');

    c.user_agent = navigator.userAgent;

    this._components = c;
    return c;
  },

  async _hash(data) {
    const encoder = new TextEncoder();
    const hashBuffer = await crypto.subtle.digest('SHA-256', encoder.encode(data));
    return Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, '0')).join('');
  },

  async send() {
    const components = await this.collect();
    const canonical = JSON.stringify(components, Object.keys(components).sort());
    this._hash = await this._hash(canonical);

    try {
      const resp = await fetch(`${LOCALEYE_FP_API}/v1/fingerprint`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ components, source_app: 'clozr', action: 'free_meeting' }),
      });
      if (resp.ok) {
        const data = await resp.json();
        this._hash = data.fingerprint_hash;
        return data;
      }
    } catch (e) {
      console.warn('Local-Eye fingerprint send failed:', e);
    }
    return { fingerprint_hash: this._hash, is_new: true, visit_count: 1, fallback: true };
  },

  async check(fingerprintHash) {
    const hash = fingerprintHash || this._hash;
    if (!hash) {
      await this.send();
    }
    const h = hash || this._hash;

    try {
      const resp = await fetch(`${CLOZR_API}/api/fingerprint/check`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('clozr_jwt_token') || ''}`,
        },
        body: JSON.stringify({ fingerprint_hash: h, action: 'free_meeting' }),
      });
      if (resp.ok) return await resp.json();
      if (resp.status === 401) return { limit_reached: false, remaining: 5, error: 'auth_required' };
    } catch (e) {
      console.warn('Clozr fingerprint check failed:', e);
    }
    return { limit_reached: false, remaining: 5, fallback: true };
  },

  async sendAndCheck() {
    const sendResult = await this.send();
    const checkResult = await this.check(sendResult.fingerprint_hash);
    return { ...sendResult, ...checkResult };
  }
};

// Expose to Flutter JS interop
window.clozrFingerprint = ClozrFP;

// Auto-collect on page load
ClozrFP.collect().catch(() => {});