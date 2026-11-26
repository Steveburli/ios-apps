// Synthesised sound: engine hum, horn, chimes. Starts after the first click.
export class Sound {
  constructor() { this.ctx = null; this.muted = false; }

  start() {
    if (this.ctx) { this.ctx.resume?.(); return; }
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      this.ctx = new AC();
    } catch { return; }
    const c = this.ctx;
    this.master = c.createGain();
    this.master.gain.value = 0.55;
    this.master.connect(c.destination);
    // engine: two detuned saws through a low-pass filter
    this.engGain = c.createGain(); this.engGain.gain.value = 0;
    this.engFilter = c.createBiquadFilter(); this.engFilter.type = 'lowpass'; this.engFilter.frequency.value = 400;
    this.engFilter.connect(this.engGain); this.engGain.connect(this.master);
    this.osc = [c.createOscillator(), c.createOscillator()];
    this.osc[0].type = 'sawtooth'; this.osc[1].type = 'square';
    this.osc.forEach((o, i) => { o.frequency.value = 40 + i; const g = c.createGain(); g.gain.value = i ? 0.25 : 0.5; o.connect(g); g.connect(this.engFilter); o.start(); });
    // tyre / wind noise
    const buf = c.createBuffer(1, c.sampleRate * 2, c.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    this.noise = c.createBufferSource(); this.noise.buffer = buf; this.noise.loop = true;
    this.noiseFilter = c.createBiquadFilter(); this.noiseFilter.type = 'bandpass'; this.noiseFilter.frequency.value = 800;
    this.noiseGain = c.createGain(); this.noiseGain.gain.value = 0;
    this.noise.connect(this.noiseFilter); this.noiseFilter.connect(this.noiseGain); this.noiseGain.connect(this.master);
    this.noise.start();
  }

  setMuted(m) {
    this.muted = m;
    if (this.master) this.master.gain.value = m ? 0 : 0.55;
  }

  engine(on, speed, throttle, skid) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const gearSpan = 9;
    const gear = Math.min(5, Math.floor(Math.abs(speed) / gearSpan));
    const rpm = (Math.abs(speed) - gear * gearSpan) / gearSpan;
    const f = 38 + rpm * 55 + gear * 6 + throttle * 12;
    this.osc[0].frequency.setTargetAtTime(f, t, 0.05);
    this.osc[1].frequency.setTargetAtTime(f * 1.5, t, 0.05);
    this.engFilter.frequency.setTargetAtTime(250 + throttle * 700 + rpm * 300, t, 0.08);
    this.engGain.gain.setTargetAtTime(on ? 0.16 + throttle * 0.12 : 0, t, 0.1);
    this.noiseGain.gain.setTargetAtTime(on ? Math.min(0.08, Math.abs(speed) * 0.0022) + (skid ? 0.12 : 0) : 0, t, 0.1);
    this.noiseFilter.frequency.setTargetAtTime(skid ? 2400 : 600 + Math.abs(speed) * 20, t, 0.1);
  }

  tone(freq, dur, type = 'sine', vol = 0.2, when = 0, slide = 0) {
    if (!this.ctx) return;
    const c = this.ctx, t = c.currentTime + when;
    const o = c.createOscillator(), g = c.createGain();
    o.type = type; o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(freq * slide, t + dur);
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(vol, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(this.master);
    o.start(t); o.stop(t + dur + 0.05);
  }

  horn() { this.tone(392, 0.5, 'square', 0.12); this.tone(494, 0.5, 'square', 0.1); }
  bell() { this.tone(2093, 0.5, 'sine', 0.12); this.tone(2637, 0.45, 'sine', 0.08, 0.02); this.tone(2093, 0.4, 'sine', 0.1, 0.18); }
  smallHorn() { this.tone(523, 0.18, 'square', 0.07); this.tone(523, 0.18, 'square', 0.07, 0.25); }
  coin() { this.tone(988, 0.12, 'square', 0.08); this.tone(1319, 0.3, 'square', 0.08, 0.08); }
  bump(s) { this.tone(90, 0.25, 'triangle', Math.min(0.4, s * 0.04), 0, 0.5); }
  door() { this.tone(180, 0.08, 'square', 0.08); this.tone(120, 0.1, 'square', 0.08, 0.06); }
  blip() { this.tone(660, 0.08, 'sine', 0.12); }
  checkpoint() { this.tone(784, 0.12, 'triangle', 0.18); this.tone(1175, 0.25, 'triangle', 0.18, 0.1); }
  success() { [523, 659, 784, 1047].forEach((f, i) => this.tone(f, 0.35, 'triangle', 0.18, i * 0.12)); }
  fail() { [392, 330, 262].forEach((f, i) => this.tone(f, 0.4, 'triangle', 0.16, i * 0.18)); }
  splash() { this.tone(300, 0.5, 'sawtooth', 0.08, 0, 0.3); }
}
