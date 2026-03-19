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
		var env, sig, body, noise;
		env = EnvGen.kr(Env.asr(0.2, 1.0, 0.6), gate: gate, doneAction: 2);
		body = (
			SinOsc.ar(freq) * 0.45
			+ SinOsc.ar(freq * 1.5, 0.3) * 0.25
			+ SinOsc.ar(freq * 2.0, 1.2) * 0.18
		);
		noise = BrownNoise.ar(0.08);
		sig = RLPF.ar(body + noise, cutoff.clip(80, 8000), 0.22);
		sig = Pan2.ar(sig * env * amp.clip(0, 1), pan.clip(-1, 1));
		Out.ar(out, sig.tanh);
	}).add;

	SynthDef(\vrb_onset, { |out=0, gate=1, amp=0.4, freq=440, pan=0|
		var env, tone, noise, sig;
		env = EnvGen.ar(Env.perc(0.001, 0.22, 1.0, -4), gate: gate, doneAction: 2);
		tone = (
			SinOsc.ar(freq) * 0.6
			+ SinOsc.ar(freq * 2.0) * 0.28
			+ SinOsc.ar(freq * 3.0) * 0.12
		);
		noise = WhiteNoise.ar(0.15);
		sig = Pan2.ar((tone + noise) * env * amp.clip(0, 1), pan.clip(-1, 1));
		Out.ar(out, sig.tanh);
	}).add;

	SynthDef(\vrb_impact, { |out=0, gate=1, amp=0.5, freq=180, pan=0|
		var env, pitch, click, body, sig;
		env = EnvGen.ar(Env.perc(0.001, 0.35, 1.0, -6), gate: gate, doneAction: 2);
		pitch = XLine.kr(freq * 2.8, freq.max(40), 0.16);
		click = WhiteNoise.ar(0.3) * EnvGen.ar(Env.perc(0.0005, 0.03, 1.0, -8));
		body = SinOsc.ar(pitch, 0, 0.75);
		sig = Pan2.ar((body + click) * env * amp.clip(0, 1), pan.clip(-1, 1));
		Out.ar(out, sig.tanh);
	}).add;

	SynthDef(\vrb_enter, { |out=0, gate=1, amp=0.4, freq=220, pan=0|
		var env, pitch, sig;
		env = EnvGen.ar(Env.perc(0.01, 1.0, 1.0, -3), gate: gate, doneAction: 2);
		pitch = XLine.kr((freq * 0.5).max(40), freq * 2.4, 0.9);
		sig = Saw.ar(pitch, 0.16) + SinOsc.ar(pitch * 0.5, 0, 0.2);
		sig = Pan2.ar(sig * env * amp.clip(0, 1), pan.clip(-1, 1));
		Out.ar(out, sig.tanh);
	}).add;

	SynthDef(\vrb_exit, { |out=0, gate=1, amp=0.4, freq=240, pan=0|
		var env, pitch, sig;
		env = EnvGen.ar(Env.perc(0.01, 0.9, 1.0, -4), gate: gate, doneAction: 2);
		pitch = XLine.kr(freq.max(50), (freq * 0.25).max(30), 0.8);
		sig = Pulse.ar(pitch, 0.35, 0.18) + SinOsc.ar(pitch * 0.5, 0, 0.22);
		sig = LPF.ar(sig, (freq * 6).clip(120, 4000));
		sig = Pan2.ar(sig * env * amp.clip(0, 1), pan.clip(-1, 1));
		Out.ar(out, sig.tanh);
	}).add;

	SynthDef(\vrb_flow_burst, { |out=0, gate=1, amp=0.45, freq=900, pan=0|
		var env, center, sig;
		env = EnvGen.ar(Env.perc(0.005, 0.5, 1.0, -4), gate: gate, doneAction: 2);
		center = LFNoise1.kr(10).exprange((freq * 0.4).max(80), (freq * 1.8).clip(120, 5000));
		sig = BPF.ar(WhiteNoise.ar(0.8), center, 0.15)
			+ BPF.ar(PinkNoise.ar(0.35), center * 0.7, 0.22);
		sig = Pan2.ar(sig * env * amp.clip(0, 1), pan.clip(-1, 1));
		Out.ar(out, sig.tanh);
	}).add;

	SynthDef(\vrb_delay, { |out=0, gate=1, inbus=0, delaytime=0.2, feedback=0.25|
		var env, input, delayed;
		env = EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate: gate, doneAction: 2);
		input = In.ar(inbus, 2);
		delayed = input + CombC.ar(input, 1.0, delaytime.clip(0.01, 0.95), feedback.clip(0.01, 0.99) * 4.0);
		ReplaceOut.ar(out, (delayed * env).tanh);
	}).add;

	SynthDef(\vrb_reverb, { |out=0, gate=1, inbus=0, mix=0.18, room=0.55, damp=0.45|
		var env, input, wetL, wetR;
		env = EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate: gate, doneAction: 2);
		input = In.ar(inbus, 2);
		# wetL, wetR = FreeVerb2.ar(input[0], input[1], mix.clip(0, 1), room.clip(0, 1), damp.clip(0, 1));
		ReplaceOut.ar(out, ([wetL, wetR] * env).tanh);
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
		var values, amp, freq;
		values = makeNamedValueParser.(msg);
		amp = values.at(\amp);
		freq = values.at(\freq);
		if(amp.isNil) { amp = 0.45 };
		if(freq.isNil) { freq = 320 };
		Synth(\vrb_enter, [\out, ~fxBus.index, \amp, amp.asFloat, \freq, freq.asFloat, \pan, 0.0]);
		~bodyTargetAmp = amp.asFloat.clip(0, 1);
		updateDetected.(1);
	}, '/trigger/person_enter', recvPort: NetAddr.langPort);

	OSCdef(\personExit, { |msg|
		var values, amp, freq;
		values = makeNamedValueParser.(msg);
		amp = values.at(\amp);
		freq = values.at(\freq);
		if(amp.isNil) { amp = 0.35 };
		if(freq.isNil) { freq = 180 };
		Synth(\vrb_exit, [\out, ~fxBus.index, \amp, amp.asFloat, \freq, freq.asFloat, \pan, 0.0]);
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
