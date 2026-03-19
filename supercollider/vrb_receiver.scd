(
// Section 1: boot server with stable audio settings for this project.
s.options.numInputBusChannels = 0;
s.options.sampleRate = 44100;
s.waitForBoot {
	"virtual-real-body: server booted".postln;
	("listening on langPort=" ++ NetAddr.langPort).postln;
};
s.boot;
)

(
// Section 2: SynthDef definitions, node setup, and OSC receivers.
var makeNamedValueParser, firstValue;

makeNamedValueParser = { |msg|
	var args, dictionary, i, key, symbolKey, value;
	args = msg[1..].asArray;
	dictionary = IdentityDictionary.new;
	i = 0;
	while { i < args.size } {
		key = args[i];
		value = if((i + 1) < args.size) { args[i + 1] } { nil };
		if(value.notNil) {
			symbolKey = if(key.isKindOf(Symbol)) {
				key
			} {
				if(key.isKindOf(String)) { key.asSymbol } { nil }
			};
			if(symbolKey.notNil) {
				dictionary.put(symbolKey, value);
				i = i + 2;
			} {
				i = i + 1;
			};
		} {
			i = i + 1;
		};
	};
	dictionary;
};

firstValue = { |msg, fallback=0.0|
	if(msg.size > 1) { msg[1].asFloat } { fallback };
};

s.waitForBoot {
	var makeTrigger, setBodyState, updateDetected;

	SynthDef(\vrb_body, { |out=0, gate=1, freq=220, amp=0.0, cutoff=1200, pan=0|
		var env, freqCtl, ampCtl, cutoffCtl, panCtl, motion, sub, torso, formant, breath, shimmer, sig, drive;
		freqCtl = Lag.kr(freq.clip(40, 2200), 0.08);
		ampCtl = Lag.kr(amp.clip(0, 1), 0.12);
		cutoffCtl = Lag.kr(cutoff.clip(120, 9000), 0.12);
		panCtl = Lag.kr(pan.clip(-1, 1), 0.1);
		env = EnvGen.kr(Env.asr(0.25, 1.0, 1.2), gate: gate, doneAction: 2);
		motion = LFNoise2.kr(ampCtl.linlin(0.0, 1.0, 0.6, 8.0)).range(0.985, 1.015);
		sub = SinOsc.ar(freqCtl * 0.5 * motion, 0, 0.24);
		torso = (
			VarSaw.ar(freqCtl * motion, 0, 0.42, 0.18)
			+ SinOsc.ar(freqCtl, 0.2, 0.16)
			+ SinOsc.ar(freqCtl * 1.503 * motion, 0.5, 0.12)
			+ SinOsc.ar(freqCtl * 2.01, 1.1, 0.08)
		);
		torso = RLPF.ar(torso, cutoffCtl, 0.22);
		formant = (
			BPF.ar(Saw.ar(freqCtl * 0.5, 0.15), (cutoffCtl * 0.45).clip(120, 6000), 0.18)
			+ BPF.ar(Saw.ar(freqCtl * 0.25, 0.1), (cutoffCtl * 0.9).clip(180, 8000), 0.12)
		) * (0.18 + (ampCtl * 0.25));
		breath = HPF.ar(PinkNoise.ar(0.12), (cutoffCtl * 0.35).clip(120, 3200)) * (0.05 + (ampCtl * 0.18));
		shimmer = BPF.ar(GrayNoise.ar(0.08), (cutoffCtl * 1.4).clip(400, 12000), 0.08) * (0.03 + (ampCtl * 0.12));
		sig = LeakDC.ar(sub + torso + formant + breath + shimmer);
		sig = LPF.ar(sig, (cutoffCtl * 1.2).clip(160, 12000));
		sig = HPF.ar(sig, 35);
		drive = 1.15 + (ampCtl * 2.6);
		sig = (sig * drive).tanh / drive.sqrt;
		sig = Pan2.ar(sig * env * ampCtl, panCtl);
		Out.ar(out, sig);
	}).add;

	SynthDef(\vrb_onset, { |out=0, gate=1, amp=0.4, freq=440, pan=0|
		var env, strikeEnv, bodyEnv, freqCtl, panCtl, strike, body, air, sig;
		freqCtl = freq.clip(80, 4000);
		panCtl = pan.clip(-1, 1);
		env = EnvGen.ar(Env.perc(0.001, 0.28, 1.0, -4), gate: gate, doneAction: 2);
		strikeEnv = EnvGen.ar(Env.perc(0.0005, 0.03, 1.0, -12));
		bodyEnv = EnvGen.ar(Env.perc(0.001, 0.18, 1.0, -6));
		strike = BPF.ar(WhiteNoise.ar(0.6), (freqCtl * 3.2).clip(900, 7000), 0.18) * strikeEnv;
		body = (
			SinOsc.ar(freqCtl, 0, 0.5)
			+ SinOsc.ar(freqCtl * 2.01, 0.4, 0.18)
			+ VarSaw.ar(freqCtl * 0.5, 0, 0.3, 0.14)
		) * bodyEnv;
		air = HPF.ar(PinkNoise.ar(0.14), 3000) * EnvGen.ar(Env.perc(0.002, 0.08, 1.0, -8));
		sig = (body + strike + air) * env * amp.clip(0, 1);
		sig = Pan2.ar(sig.tanh, panCtl);
		Out.ar(out, sig);
	}).add;

	SynthDef(\vrb_impact, { |out=0, gate=1, amp=0.5, freq=180, pan=0|
		var env, pitch, thumpEnv, crackEnv, freqCtl, panCtl, exc, thump, ring, crack, sig;
		freqCtl = freq.clip(40, 1200);
		panCtl = pan.clip(-1, 1);
		env = EnvGen.ar(Env.perc(0.001, 0.48, 1.0, -6), gate: gate, doneAction: 2);
		pitch = XLine.kr(freqCtl * 3.4, freqCtl.max(40), 0.18);
		thumpEnv = EnvGen.ar(Env.perc(0.0005, 0.22, 1.0, -7));
		crackEnv = EnvGen.ar(Env.perc(0.0005, 0.028, 1.0, -10));
		exc = WhiteNoise.ar(0.55) * crackEnv;
		thump = (SinOsc.ar(pitch, 0, 0.8) + SinOsc.ar(pitch * 0.51, 0, 0.25)) * thumpEnv;
		ring = Ringz.ar(exc, (freqCtl * 2.2).clip(120, 5000), 0.12, 0.16);
		crack = HPF.ar(exc, 1800);
		sig = (thump + ring + crack) * env * amp.clip(0, 1);
		sig = LPF.ar(sig, (freqCtl * 14).clip(300, 7000));
		sig = Pan2.ar(sig.tanh, panCtl);
		Out.ar(out, sig);
	}).add;

	SynthDef(\vrb_enter, { |out=0, gate=1, amp=0.4, freq=220, pan=0|
		var env, pitch, freqCtl, panCtl, body, shimmer, sig;
		freqCtl = freq.clip(80, 1200);
		panCtl = pan.clip(-1, 1);
		env = EnvGen.ar(Env.perc(0.01, 1.2, 1.0, -4), gate: gate, doneAction: 2);
		pitch = XLine.kr((freqCtl * 0.65).max(40), freqCtl * 2.8, 0.9);
		body = (
			VarSaw.ar(pitch * 0.5, 0, 0.35, 0.12)
			+ VarSaw.ar(pitch, 0, 0.42, 0.15)
			+ SinOsc.ar(pitch * 1.5, 0.3, 0.1)
		);
		shimmer = BPF.ar(
			WhiteNoise.ar(0.24),
			XLine.kr((freqCtl * 4).clip(600, 3000), (freqCtl * 8).clip(1200, 9000), 0.7),
			0.2
		) * EnvGen.ar(Env.perc(0.02, 0.7, 1.0, -6));
		sig = HPF.ar(body, 70) + shimmer;
		sig = RLPF.ar(sig, (freqCtl * 10).clip(700, 7000), 0.3);
		sig = Pan2.ar((sig * env * amp.clip(0, 1)).tanh, panCtl);
		Out.ar(out, sig);
	}).add;

	SynthDef(\vrb_exit, { |out=0, gate=1, amp=0.4, freq=240, pan=0|
		var env, pitch, freqCtl, panCtl, body, dust, sig;
		freqCtl = freq.clip(50, 1600);
		panCtl = pan.clip(-1, 1);
		env = EnvGen.ar(Env.perc(0.01, 1.0, 1.0, -5), gate: gate, doneAction: 2);
		pitch = XLine.kr(freqCtl.max(60), (freqCtl * 0.22).max(30), 0.85);
		body = (
			Pulse.ar(pitch, 0.36, 0.16)
			+ SinOsc.ar(pitch * 0.5, 0, 0.22)
			+ Blip.ar(pitch * 0.25, 4, 0.08)
		);
		dust = HPF.ar(BrownNoise.ar(0.1), 900) * EnvGen.ar(Env.perc(0.015, 0.5, 1.0, -8));
		sig = LPF.ar(body, XLine.kr((freqCtl * 8).clip(240, 5000), 180, 0.75)) + dust;
		sig = Pan2.ar((sig * env * amp.clip(0, 1)).tanh, panCtl);
		Out.ar(out, sig);
	}).add;

	SynthDef(\vrb_flow_burst, { |out=0, gate=1, amp=0.45, freq=900, pan=0|
		var env, center, freqCtl, panCtl, swirl, ring, sig;
		freqCtl = freq.clip(120, 4000);
		panCtl = pan.clip(-1, 1);
		env = EnvGen.ar(Env.perc(0.004, 0.65, 1.0, -4), gate: gate, doneAction: 2);
		center = LFNoise2.kr(14).exprange((freqCtl * 0.35).max(120), (freqCtl * 2.5).clip(400, 8000));
		swirl = (
			BPF.ar(WhiteNoise.ar(0.75), center, 0.12)
			+ BPF.ar(PinkNoise.ar(0.45), (center * 0.62).clip(120, 7000), 0.18)
			+ HPF.ar(GrayNoise.ar(0.18), 2500)
		);
		ring = (
			Ringz.ar(Dust2.ar(24), (center * 0.5).clip(150, 5000), 0.08, 0.08)
			+ Ringz.ar(Dust2.ar(18), (center * 0.9).clip(220, 7000), 0.06, 0.06)
			+ Ringz.ar(Dust2.ar(12), (center * 1.4).clip(320, 9000), 0.05, 0.05)
		);
		sig = (swirl + ring) * env * amp.clip(0, 1);
		sig = Pan2.ar(sig.tanh, panCtl);
		Out.ar(out, sig);
	}).add;

	SynthDef(\vrb_delay, { |out=0, gate=1, inbus=0, delaytime=0.2, feedback=0.25|
		var env, input, filtered, delayed;
		env = EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate: gate, doneAction: 2);
		input = In.ar(inbus, 2);
		filtered = HPF.ar(LPF.ar(input, 7000), 80);
		delayed = input + CombC.ar(filtered, 1.0, delaytime.clip(0.01, 0.95), feedback.clip(0.01, 0.99) * 3.6);
		ReplaceOut.ar(out, LeakDC.ar((delayed * env)).tanh);
	}).add;

	SynthDef(\vrb_reverb, { |out=0, gate=1, inbus=0, mix=0.18, room=0.55, damp=0.45|
		var env, input, wetL, wetR;
		env = EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate: gate, doneAction: 2);
		input = HPF.ar(In.ar(inbus, 2), 60);
		# wetL, wetR = FreeVerb2.ar(input[0], input[1], mix.clip(0, 1), room.clip(0, 1), damp.clip(0, 1));
		ReplaceOut.ar(out, LeakDC.ar(([wetL, wetR] * env)).tanh);
	}).add;

	s.sync;

	~fxBus = Bus.audio(s, 2);
	~masterBus = Bus.audio(s, 2);
	~bodyDetected = 0;
	~bodyTargetAmp = 0.0;
	~bodyParams = (
		freq: 220.0,
		amp: 0.0,
		cutoff: 1200.0,
		pan: 0.0
	);

	~body = Synth.head(s, \vrb_body, [
		\out, ~fxBus.index,
		\freq, ~bodyParams[\freq],
		\amp, ~bodyParams[\amp],
		\cutoff, ~bodyParams[\cutoff],
		\pan, ~bodyParams[\pan]
	]);

	~delay = Synth.new(\vrb_delay, [
		\inbus, ~fxBus.index,
		\out, ~masterBus.index,
		\delaytime, 0.2,
		\feedback, 0.25
	], s, \addToTail);

	~reverb = Synth.new(\vrb_reverb, [
		\inbus, ~masterBus.index,
		\out, 0,
		\mix, 0.18,
		\room, 0.55
	], s, \addToTail);

	setBodyState = {
		var nextAmp;
		nextAmp = if(~bodyDetected > 0) { ~bodyTargetAmp } { 0.0 };
		if(~body.notNil) {
			~body.set(
				\freq, ~bodyParams[\freq],
				\amp, nextAmp.clip(0, 1),
				\cutoff, ~bodyParams[\cutoff],
				\pan, ~bodyParams[\pan]
			);
		};
	};

	updateDetected = { |value|
		~bodyDetected = value.asInteger.clip(0, 1);
		setBodyState.();
	};

	makeTrigger = { |name, defaults|
		{ |msg|
			var values, amp, freq, pan;
			values = makeNamedValueParser.(msg);
			amp = values.at(\amp);
			freq = values.at(\freq);
			pan = values.at(\pan);
			if(amp.isNil) { amp = defaults[\amp] };
			if(freq.isNil) { freq = defaults[\freq] };
			if(pan.isNil) { pan = defaults[\pan] };
			Synth(name, [
				\out, ~fxBus.index,
				\amp, amp.asFloat,
				\freq, freq.asFloat,
				\pan, pan.asFloat
			]);
		};
	};

	OSCdef(\body, { |msg|
		var values, freq, amp, cutoff, pan;
		values = makeNamedValueParser.(msg);
		freq = values.at(\freq);
		amp = values.at(\amp);
		cutoff = values.at(\cutoff);
		pan = values.at(\pan);
		if(freq.notNil) { ~bodyParams[\freq] = freq.asFloat };
		if(amp.notNil) { ~bodyTargetAmp = amp.asFloat.clip(0, 1) };
		if(cutoff.notNil) { ~bodyParams[\cutoff] = cutoff.asFloat.clip(80, 8000) };
		if(pan.notNil) { ~bodyParams[\pan] = pan.asFloat.clip(-1, 1) };
		setBodyState.();
	}, '/synth/body', recvPort: NetAddr.langPort);

	OSCdef(\reverbMix, { |msg|
		~reverb.set(\mix, firstValue.(msg, 0.18).clip(0, 1));
	}, '/fx/reverb/mix', recvPort: NetAddr.langPort);

	OSCdef(\reverbRoom, { |msg|
		~reverb.set(\room, firstValue.(msg, 0.55).clip(0, 1));
	}, '/fx/reverb/room', recvPort: NetAddr.langPort);

	OSCdef(\delayTime, { |msg|
		~delay.set(\delaytime, firstValue.(msg, 0.2).clip(0.01, 0.95));
	}, '/fx/delay/time', recvPort: NetAddr.langPort);

	OSCdef(\delayFeedback, { |msg|
		~delay.set(\feedback, firstValue.(msg, 0.25).clip(0.01, 0.99));
	}, '/fx/delay/feedback', recvPort: NetAddr.langPort);

	OSCdef(\motionOnset, makeTrigger.(\vrb_onset, (amp: 0.4, freq: 440, pan: 0.0)), '/trigger/motion_onset', recvPort: NetAddr.langPort);
	OSCdef(\impact, makeTrigger.(\vrb_impact, (amp: 0.5, freq: 180, pan: 0.0)), '/trigger/impact', recvPort: NetAddr.langPort);
	OSCdef(\flowBurst, makeTrigger.(\vrb_flow_burst, (amp: 0.4, freq: 900, pan: 0.0)), '/trigger/flow_burst', recvPort: NetAddr.langPort);

	OSCdef(\personEnter, { |msg|
		var values, amp, freq, pan;
		values = makeNamedValueParser.(msg);
		amp = values.at(\amp);
		freq = values.at(\freq);
		pan = values.at(\pan);
		if(amp.isNil) { amp = 0.45 };
		if(freq.isNil) { freq = 320 };
		if(pan.isNil) { pan = 0.0 };
		Synth(\vrb_enter, [\out, ~fxBus.index, \amp, amp.asFloat, \freq, freq.asFloat, \pan, pan.asFloat]);
		~bodyParams[\freq] = freq.asFloat.clip(40, 2200);
		~bodyParams[\pan] = pan.asFloat.clip(-1, 1);
		~bodyTargetAmp = amp.asFloat.clip(0, 1);
		updateDetected.(1);
	}, '/trigger/person_enter', recvPort: NetAddr.langPort);

	OSCdef(\personExit, { |msg|
		var values, amp, freq, pan;
		values = makeNamedValueParser.(msg);
		amp = values.at(\amp);
		freq = values.at(\freq);
		pan = values.at(\pan);
		if(amp.isNil) { amp = 0.35 };
		if(freq.isNil) { freq = 180 };
		if(pan.isNil) { pan = 0.0 };
		Synth(\vrb_exit, [\out, ~fxBus.index, \amp, amp.asFloat, \freq, freq.asFloat, \pan, pan.asFloat]);
		~bodyParams[\pan] = pan.asFloat.clip(-1, 1);
		updateDetected.(0);
	}, '/trigger/person_exit', recvPort: NetAddr.langPort);

	OSCdef(\detected, { |msg|
		updateDetected.(firstValue.(msg, 0).asInteger);
	}, '/vrb/meta/detected', recvPort: NetAddr.langPort);

	"virtual-real-body: OSCdefs registered".postln;
};
)

(
// Section 3: cleanup and stop.
OSCdef(\body).free;
OSCdef(\reverbMix).free;
OSCdef(\reverbRoom).free;
OSCdef(\delayTime).free;
OSCdef(\delayFeedback).free;
OSCdef(\motionOnset).free;
OSCdef(\impact).free;
OSCdef(\personEnter).free;
OSCdef(\personExit).free;
OSCdef(\flowBurst).free;
OSCdef(\detected).free;

if(~body.notNil) { ~body.set(\gate, 0) };
if(~reverb.notNil) { ~reverb.set(\gate, 0) };
if(~delay.notNil) { ~delay.set(\gate, 0) };
if(~masterBus.notNil) { ~masterBus.free };
if(~fxBus.notNil) { ~fxBus.free };
)
