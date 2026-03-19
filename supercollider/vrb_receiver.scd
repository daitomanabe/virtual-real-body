// Section 1: boot server with stable audio settings for this project.
s.options.numInputBusChannels = 0;
s.options.sampleRate = 44100;
s.waitForBoot {
	"virtual-real-body: server booted".postln;
	("listening on langPort=" ++ NetAddr.langPort).postln;
};
s.boot;

// Section 2: SynthDef definitions, node setup, and OSC receivers.
{
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
		var makeTrigger, setBodyState, refreshFxState, updateDetected, updateTriggerState;

		SynthDef(\vrb_body, {
			|out=0, gate=1, freq=220, amp=0.0, cutoff=1200, pan=0, mode=0, texture=0.35, noiseMix=0.18, subMix=0.55, motion=0.35, resonance=0.22|
			var env, freqCtl, ampCtl, cutoffCtl, panCtl, modeCtl, textureCtl, noiseCtl, subCtl, motionCtl, resonanceCtl;
			var motionLfo, layerA, layerB, layerC, layerD, harmonic, breath, click, sig, drive;
			freqCtl = Lag.kr(freq.clip(35, 2400), 0.08);
			ampCtl = Lag.kr(amp.clip(0, 1), 0.14);
			cutoffCtl = Lag.kr(cutoff.clip(120, 10000), 0.14);
			panCtl = Lag.kr(pan.clip(-1, 1), 0.1);
			modeCtl = Lag.kr(mode.clip(0, 3), 0.18);
			textureCtl = Lag.kr(texture.clip(0, 1), 0.18);
			noiseCtl = Lag.kr(noiseMix.clip(0, 1), 0.18);
			subCtl = Lag.kr(subMix.clip(0, 1), 0.18);
			motionCtl = Lag.kr(motion.clip(0, 1), 0.18);
			resonanceCtl = Lag.kr(resonance.clip(0.08, 0.95), 0.16);
			env = EnvGen.kr(Env.asr(0.25, 1.0, 1.3), gate: gate, doneAction: 2);
			motionLfo = LFNoise2.kr(motionCtl.linlin(0.0, 1.0, 0.25, 6.0)).range(
				1.0 - (motionCtl * 0.08),
				1.0 + (motionCtl * 0.08)
			);

			layerA = (
				SinOsc.ar(freqCtl * 0.5 * motionLfo, 0, 0.36 * subCtl)
				+ VarSaw.ar(freqCtl * motionLfo, 0, textureCtl.linlin(0.0, 1.0, 0.24, 0.72), 0.18)
				+ SinOsc.ar(freqCtl * 1.5, 0.3, 0.12)
			);

			layerB = (
				Pulse.ar(freqCtl * motionLfo, textureCtl.linlin(0.0, 1.0, 0.22, 0.62), 0.14)
				+ Blip.ar(freqCtl * 0.5, textureCtl.linlin(0.0, 1.0, 3.0, 18.0), 0.18)
				+ SinOsc.ar(freqCtl * 2.0, 0, 0.1)
			);

			layerC = (
				Formant.ar(
					freqCtl * [1.0, 1.004],
					(cutoffCtl * textureCtl.linlin(0.0, 1.0, 0.45, 1.1)).clip(250, 5000),
					(cutoffCtl * textureCtl.linlin(0.0, 1.0, 0.12, 0.32)).clip(120, 1800)
				).sum * 0.12
				+ SinOsc.ar(freqCtl * 0.5, 0, 0.2 * subCtl)
				+ Saw.ar(freqCtl * 0.25, 0.08)
			);

			layerD = (
				PMOsc.ar(
					freqCtl * motionLfo,
					(freqCtl * textureCtl.linlin(0.0, 1.0, 1.5, 4.5)).clip(60, 9000),
					textureCtl.linlin(0.0, 1.0, 0.2, 3.0),
					0,
					0.18
				)
				+ SinOsc.ar(freqCtl * 0.25, 0, 0.18 * subCtl)
				+ VarSaw.ar(freqCtl * 2.0, 0, 0.2, 0.06)
			);

			harmonic = SelectX.ar(modeCtl, [layerA, layerB, layerC, layerD]);
			harmonic = RLPF.ar(harmonic, cutoffCtl, resonanceCtl);
			breath = HPF.ar(PinkNoise.ar(0.16), (cutoffCtl * 0.3).clip(150, 3400)) * noiseCtl * (0.12 + (ampCtl * 0.12));
			click = BPF.ar(GrayNoise.ar(0.08), (cutoffCtl * 1.5).clip(800, 12000), 0.12) * (textureCtl * 0.12);
			sig = LeakDC.ar(harmonic + breath + click);
			sig = HPF.ar(sig, 30);
			drive = 1.1 + (ampCtl * 2.2) + (textureCtl * 1.4);
			sig = (sig * drive).tanh / drive.sqrt;
			sig = Pan2.ar(sig * env * ampCtl, panCtl);
			Out.ar(out, sig);
		}).add;

		SynthDef(\vrb_onset, { |out=0, gate=1, amp=0.4, freq=440, pan=0, mode=0, color=0.35|
			var env, modeCtl, colorCtl, freqCtl, panCtl, bodyA, bodyB, bodyC, bodyD, sig;
			freqCtl = freq.clip(80, 4000);
			panCtl = pan.clip(-1, 1);
			modeCtl = mode.clip(0, 3);
			colorCtl = color.clip(0, 1);
			env = EnvGen.ar(Env.perc(0.001, 0.28, 1.0, -4), gate: gate, doneAction: 2);
			bodyA = (
				BPF.ar(WhiteNoise.ar(0.7), (freqCtl * 3.0).clip(900, 7000), 0.16) * EnvGen.ar(Env.perc(0.0005, 0.03, 1.0, -12))
				+ SinOsc.ar(freqCtl, 0, 0.55) * EnvGen.ar(Env.perc(0.001, 0.18, 1.0, -6))
			);
			bodyB = (
				Ringz.ar(Impulse.ar(0), (freqCtl * [1.0, 1.6, 2.3]).clip(120, 9000), 0.08).sum * 0.3
				+ HPF.ar(WhiteNoise.ar(0.4), 2400) * EnvGen.ar(Env.perc(0.0005, 0.08, 1.0, -10))
			);
			bodyC = (
				PMOsc.ar(freqCtl, (freqCtl * 2.4).clip(160, 9000), colorCtl.linlin(0.0, 1.0, 0.3, 2.0), 0, 0.34)
				+ VarSaw.ar(freqCtl * 0.5, 0, 0.3, 0.12)
			);
			bodyD = (
				Blip.ar(freqCtl * 0.75, colorCtl.linlin(0.0, 1.0, 5.0, 22.0), 0.3)
				+ BPF.ar(PinkNoise.ar(0.25), (freqCtl * 4.0).clip(1200, 9000), 0.18)
			);
			sig = SelectX.ar(modeCtl, [bodyA, bodyB, bodyC, bodyD]) * (0.7 + (colorCtl * 0.5));
			sig = Pan2.ar((sig * env * amp.clip(0, 1)).tanh, panCtl);
			Out.ar(out, sig);
		}).add;

		SynthDef(\vrb_impact, { |out=0, gate=1, amp=0.5, freq=180, pan=0, mode=0, color=0.45|
			var env, modeCtl, colorCtl, freqCtl, panCtl, pitch, bodyA, bodyB, bodyC, bodyD, sig;
			freqCtl = freq.clip(35, 1600);
			panCtl = pan.clip(-1, 1);
			modeCtl = mode.clip(0, 3);
			colorCtl = color.clip(0, 1);
			env = EnvGen.ar(Env.perc(0.001, 0.5, 1.0, -6), gate: gate, doneAction: 2);
			pitch = XLine.kr(freqCtl * 3.5, freqCtl.max(35), 0.18);
			bodyA = (
				SinOsc.ar(pitch, 0, 0.78) * EnvGen.ar(Env.perc(0.0005, 0.24, 1.0, -7))
				+ HPF.ar(WhiteNoise.ar(0.35), 1800) * EnvGen.ar(Env.perc(0.0005, 0.03, 1.0, -10))
			);
			bodyB = (
				Ringz.ar(WhiteNoise.ar(0.5) * EnvGen.ar(Env.perc(0.0005, 0.05, 1.0, -10)), (freqCtl * [1.4, 2.2, 3.1]).clip(120, 8000), 0.14).sum * 0.22
				+ SinOsc.ar(pitch * 0.5, 0, 0.34)
			);
			bodyC = (
				PMOsc.ar(freqCtl * 0.7, (freqCtl * 2.8).clip(120, 9000), colorCtl.linlin(0.0, 1.0, 0.5, 3.0), 0, 0.28)
				+ BPF.ar(BrownNoise.ar(0.25), (freqCtl * 6.0).clip(300, 7000), 0.2)
			);
			bodyD = (
				CombC.ar(HPF.ar(WhiteNoise.ar(0.5), 700), 0.2, 1 / (freqCtl * 1.5).clip(80, 1400), 0.18)
				+ SinOsc.ar(pitch * 0.33, 0, 0.24)
			);
			sig = SelectX.ar(modeCtl, [bodyA, bodyB, bodyC, bodyD]) * (0.75 + (colorCtl * 0.5));
			sig = LPF.ar(sig, (freqCtl * 14).clip(250, 8000));
			sig = Pan2.ar((sig * env * amp.clip(0, 1)).tanh, panCtl);
			Out.ar(out, sig);
		}).add;

		SynthDef(\vrb_enter, { |out=0, gate=1, amp=0.4, freq=220, pan=0, mode=0, color=0.45|
			var env, modeCtl, colorCtl, freqCtl, panCtl, pitch, bodyA, bodyB, bodyC, bodyD, sig;
			freqCtl = freq.clip(80, 1800);
			panCtl = pan.clip(-1, 1);
			modeCtl = mode.clip(0, 3);
			colorCtl = color.clip(0, 1);
			env = EnvGen.ar(Env.perc(0.01, 1.25, 1.0, -4), gate: gate, doneAction: 2);
			pitch = XLine.kr((freqCtl * 0.65).max(40), freqCtl * 2.8, 0.9);
			bodyA = VarSaw.ar(pitch * [0.5, 1.0], 0, 0.36, [0.14, 0.12]).sum;
			bodyB = Formant.ar(pitch, (freqCtl * 6.0).clip(500, 5000), (freqCtl * 1.2).clip(120, 1200)) * 0.2;
			bodyC = PMOsc.ar(pitch * 0.75, (pitch * 2.2).clip(120, 9000), colorCtl.linlin(0.0, 1.0, 0.3, 2.6), 0, 0.24);
			bodyD = (
				Ringz.ar(Dust2.ar(18), (pitch * [1.0, 1.25, 1.5]).clip(140, 7000), 0.3).sum * 0.14
				+ Saw.ar(pitch * 0.25, 0.12)
			);
			sig = SelectX.ar(modeCtl, [bodyA, bodyB, bodyC, bodyD]);
			sig = sig + BPF.ar(WhiteNoise.ar(0.22), XLine.kr((freqCtl * 4).clip(700, 3000), (freqCtl * 8).clip(1200, 9000), 0.7), 0.2) * (0.16 + (colorCtl * 0.14));
			sig = RLPF.ar(sig, (freqCtl * 10).clip(800, 8000), colorCtl.linlin(0.0, 1.0, 0.18, 0.45));
			sig = Pan2.ar((sig * env * amp.clip(0, 1)).tanh, panCtl);
			Out.ar(out, sig);
		}).add;

		SynthDef(\vrb_exit, { |out=0, gate=1, amp=0.4, freq=240, pan=0, mode=0, color=0.35|
			var env, modeCtl, colorCtl, freqCtl, panCtl, pitch, bodyA, bodyB, bodyC, bodyD, sig;
			freqCtl = freq.clip(50, 1800);
			panCtl = pan.clip(-1, 1);
			modeCtl = mode.clip(0, 3);
			colorCtl = color.clip(0, 1);
			env = EnvGen.ar(Env.perc(0.01, 1.1, 1.0, -5), gate: gate, doneAction: 2);
			pitch = XLine.kr(freqCtl.max(60), (freqCtl * 0.22).max(30), 0.85);
			bodyA = Pulse.ar(pitch, 0.34, 0.18) + SinOsc.ar(pitch * 0.5, 0, 0.22);
			bodyB = Formant.ar((pitch * 0.5).clip(40, 600), (freqCtl * 3.2).clip(200, 4000), (freqCtl * 0.8).clip(90, 900)) * 0.2;
			bodyC = PMOsc.ar((pitch * 0.7).clip(40, 900), (pitch * 2.0).clip(120, 7000), colorCtl.linlin(0.0, 1.0, 0.3, 1.8), 0, 0.22);
			bodyD = CombC.ar(HPF.ar(BrownNoise.ar(0.2), 900), 0.25, 1 / (pitch * 1.3).clip(70, 1600), 0.2);
			sig = SelectX.ar(modeCtl, [bodyA, bodyB, bodyC, bodyD]);
			sig = LPF.ar(sig, XLine.kr((freqCtl * 8).clip(240, 5000), 180, 0.75)) + (HPF.ar(BrownNoise.ar(0.1), 900) * EnvGen.ar(Env.perc(0.02, 0.52, 1.0, -8)));
			sig = Pan2.ar((sig * env * amp.clip(0, 1)).tanh, panCtl);
			Out.ar(out, sig);
		}).add;

		SynthDef(\vrb_flow_burst, { |out=0, gate=1, amp=0.45, freq=900, pan=0, mode=0, color=0.5|
			var env, modeCtl, colorCtl, freqCtl, panCtl, center, bodyA, bodyB, bodyC, bodyD, sig;
			freqCtl = freq.clip(120, 5000);
			panCtl = pan.clip(-1, 1);
			modeCtl = mode.clip(0, 3);
			colorCtl = color.clip(0, 1);
			env = EnvGen.ar(Env.perc(0.004, 0.7, 1.0, -4), gate: gate, doneAction: 2);
			center = LFNoise2.kr(14).exprange((freqCtl * 0.35).max(120), (freqCtl * 2.5).clip(400, 9000));
			bodyA = (
				BPF.ar(WhiteNoise.ar(0.8), center, 0.12)
				+ BPF.ar(PinkNoise.ar(0.45), (center * 0.62).clip(120, 7000), 0.18)
			);
			bodyB = Ringz.ar(Dust2.ar(24), (center * [0.5, 0.9, 1.4]).clip(150, 9000), [0.08, 0.06, 0.05]).sum * 0.22;
			bodyC = PMOsc.ar(center.clip(120, 3000), (center * 1.8).clip(200, 9000), colorCtl.linlin(0.0, 1.0, 0.4, 2.6), 0, 0.24);
			bodyD = CombC.ar(HPF.ar(GrayNoise.ar(0.22), 1800), 0.25, 1 / center.clip(240, 1600), 0.2);
			sig = SelectX.ar(modeCtl, [bodyA, bodyB, bodyC, bodyD]) * (0.7 + (colorCtl * 0.55));
			sig = Pan2.ar((sig * env * amp.clip(0, 1)).tanh, panCtl);
			Out.ar(out, sig);
		}).add;

		SynthDef(\vrb_chorus, { |out=0, gate=1, inbus=0, mix=0.12, rate=0.18, depth=0.012|
			var env, input, wetL, wetR, sig, mixCtl, rateCtl, depthCtl;
			mixCtl = mix.clip(0, 1);
			rateCtl = rate.clip(0.02, 8.0);
			depthCtl = depth.clip(0.0001, 0.05);
			env = EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate: gate, doneAction: 2);
			input = In.ar(inbus, 2);
			wetL = DelayC.ar(input[0], 0.08, SinOsc.kr(rateCtl, 0, depthCtl, depthCtl + 0.015));
			wetR = DelayC.ar(input[1], 0.08, SinOsc.kr(rateCtl * 1.21, pi * 0.5, depthCtl, depthCtl + 0.019));
			sig = XFade2.ar(input, [wetL, wetR], mixCtl.linlin(0, 1, -1, 1));
			ReplaceOut.ar(out, LeakDC.ar(sig * env));
		}).add;

		SynthDef(\vrb_delay, { |out=0, gate=1, inbus=0, delaytime=0.2, feedback=0.25, mix=0.32, tone=0.62|
			var env, input, filtered, wet, sig, toneCtl, mixCtl;
			toneCtl = tone.clip(0, 1);
			mixCtl = mix.clip(0, 1);
			env = EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate: gate, doneAction: 2);
			input = In.ar(inbus, 2);
			filtered = HPF.ar(LPF.ar(input, toneCtl.linexp(0.0, 1.0, 1200, 10000)), toneCtl.linexp(0.0, 1.0, 40, 300));
			wet = CombC.ar(filtered, 1.0, delaytime.clip(0.01, 0.95), feedback.clip(0.01, 0.99) * 3.6);
			sig = XFade2.ar(input, wet, mixCtl.linlin(0, 1, -1, 1));
			ReplaceOut.ar(out, LeakDC.ar((sig * env)).tanh);
		}).add;

		SynthDef(\vrb_reverb, { |out=0, gate=1, inbus=0, mix=0.18, room=0.55, damp=0.45, tone=0.6|
			var env, input, wetL, wetR, wet, sig, mixCtl, toneCtl;
			mixCtl = mix.clip(0, 1);
			toneCtl = tone.clip(0, 1);
			env = EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate: gate, doneAction: 2);
			input = HPF.ar(In.ar(inbus, 2), 60);
			# wetL, wetR = FreeVerb2.ar(input[0], input[1], mixCtl, room.clip(0, 1), damp.clip(0, 1));
			wet = LPF.ar([wetL, wetR], toneCtl.linexp(0.0, 1.0, 1200, 12000));
			sig = XFade2.ar(input, wet, mixCtl.linlin(0, 1, -1, 1));
			ReplaceOut.ar(out, LeakDC.ar((sig * env)).tanh);
		}).add;

		SynthDef(\vrb_aggression, {
			|out=0, gate=1, inbus=0,
			harshOn=0, harshLevel=0.0, harshTone=0.62, harshHp=1800, harshLp=9800, harshDuck=0.22,
			hpOn=0, hpFreq=120, hpRq=0.4, hpMix=1.0,
			lpOn=0, lpFreq=9200, lpRq=0.45, lpMix=1.0,
			distOn=0, distDrive=0.0, distMix=0.0, distFold=0.0, distBias=0.0, distTone=0.68,
			glitchOn=0, glitchMix=0.0, glitchRate=8.0, glitchDepth=0.0, glitchCrush=0.0, glitchGate=0.0|
			var env, input, sig;
			var harshOnCtl, harshLevelCtl, harshToneCtl, harshHpCtl, harshLpCtl, harshDuckCtl;
			var hpOnCtl, hpFreqCtl, hpRqCtl, hpMixCtl;
			var lpOnCtl, lpFreqCtl, lpRqCtl, lpMixCtl;
			var distOnCtl, distDriveCtl, distMixCtl, distFoldCtl, distBiasCtl, distToneCtl;
			var glitchOnCtl, glitchMixCtl, glitchRateCtl, glitchDepthCtl, glitchCrushCtl, glitchGateCtl;
			var follower, harsh, harshL, harshR, hpWet, lpWet, foldSig, distWet, glitchTrig, held, crushSteps, gateMask, glitchWet;
			harshOnCtl = Lag.kr(harshOn.clip(0, 1), 0.08);
			harshLevelCtl = Lag.kr(harshLevel.clip(0, 1), 0.12);
			harshToneCtl = Lag.kr(harshTone.clip(0, 1), 0.12);
			harshHpCtl = Lag.kr(harshHp.clip(120, 12000), 0.12);
			harshLpCtl = Lag.kr(harshLp.clip(1200, 18000), 0.12);
			harshDuckCtl = Lag.kr(harshDuck.clip(0, 1), 0.12);
			hpOnCtl = Lag.kr(hpOn.clip(0, 1), 0.08);
			hpFreqCtl = Lag.kr(hpFreq.clip(20, 12000), 0.12);
			hpRqCtl = Lag.kr(hpRq.clip(0.08, 0.95), 0.12);
			hpMixCtl = Lag.kr(hpMix.clip(0, 1), 0.12);
			lpOnCtl = Lag.kr(lpOn.clip(0, 1), 0.08);
			lpFreqCtl = Lag.kr(lpFreq.clip(120, 18000), 0.12);
			lpRqCtl = Lag.kr(lpRq.clip(0.08, 0.95), 0.12);
			lpMixCtl = Lag.kr(lpMix.clip(0, 1), 0.12);
			distOnCtl = Lag.kr(distOn.clip(0, 1), 0.08);
			distDriveCtl = Lag.kr(distDrive.clip(0, 1), 0.1);
			distMixCtl = Lag.kr(distMix.clip(0, 1), 0.1);
			distFoldCtl = Lag.kr(distFold.clip(0, 1), 0.1);
			distBiasCtl = Lag.kr(distBias.clip(-1, 1), 0.1);
			distToneCtl = Lag.kr(distTone.clip(0, 1), 0.1);
			glitchOnCtl = Lag.kr(glitchOn.clip(0, 1), 0.08);
			glitchMixCtl = Lag.kr(glitchMix.clip(0, 1), 0.08);
			glitchRateCtl = Lag.kr(glitchRate.clip(0.25, 40.0), 0.1);
			glitchDepthCtl = Lag.kr(glitchDepth.clip(0, 1), 0.1);
			glitchCrushCtl = Lag.kr(glitchCrush.clip(0, 1), 0.1);
			glitchGateCtl = Lag.kr(glitchGate.clip(0, 1), 0.1);
			env = EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate: gate, doneAction: 2);
			input = In.ar(inbus, 2);
			follower = Amplitude.kr(Mix(input), 0.01, 0.12).lag(0.08);

			harsh = WhiteNoise.ar(0.55) + GrayNoise.ar(0.25);
			harsh = HPF.ar(harsh, harshHpCtl);
			harsh = BPF.ar(harsh, harshToneCtl.linexp(0.0, 1.0, 2200, 8200), 0.16) + (harsh * 0.35);
			harsh = LPF.ar(harsh, harshLpCtl);
			harsh = harsh * harshLevelCtl * harshOnCtl * (0.3 + (follower * (1.6 - (harshDuckCtl * 1.1))));
			harshL = DelayC.ar(harsh, 0.05, 0.003);
			harshR = DelayC.ar(harsh, 0.05, 0.011);
			sig = input + [harshL, harshR];

			hpWet = RHPF.ar(sig, hpFreqCtl, hpRqCtl);
			sig = XFade2.ar(sig, hpWet, (hpOnCtl * hpMixCtl).linlin(0, 1, -1, 1));

			lpWet = RLPF.ar(sig, lpFreqCtl, lpRqCtl);
			sig = XFade2.ar(sig, lpWet, (lpOnCtl * lpMixCtl).linlin(0, 1, -1, 1));

			foldSig = Fold.ar(LeakDC.ar(sig + distBiasCtl), -1.0, 1.0);
			distWet = ((sig * (1.0 + (distDriveCtl * 18.0))) + (foldSig * (0.3 + (distFoldCtl * 1.6)))).tanh;
			distWet = HPF.ar(LPF.ar(distWet, distToneCtl.linexp(0.0, 1.0, 1200, 12000)), 38);
			sig = XFade2.ar(sig, distWet, (distOnCtl * distMixCtl).linlin(0, 1, -1, 1));

			glitchTrig = Impulse.ar(glitchRateCtl);
			held = [Latch.ar(sig[0], glitchTrig), Latch.ar(sig[1], glitchTrig)];
			crushSteps = glitchCrushCtl.linexp(0.0, 1.0, 256.0, 12.0);
			glitchWet = (held * crushSteps).round / crushSteps;
			glitchWet = LeakDC.ar(glitchWet + (HPF.ar(glitchWet, 1800) * glitchDepthCtl * 0.6));
			gateMask = (1.0 - glitchGateCtl) + (
				LFPulse.kr(
					(glitchRateCtl * (0.5 + (glitchDepthCtl * 3.0))).clip(0.2, 40.0),
					0,
					(1.0 - (glitchGateCtl * 0.78)).clip(0.08, 0.98)
				) * glitchGateCtl
			);
			glitchWet = glitchWet * gateMask;
			sig = XFade2.ar(sig, glitchWet, (glitchOnCtl * glitchMixCtl).linlin(0, 1, -1, 1));

			ReplaceOut.ar(out, LeakDC.ar(sig * env));
		}).add;

		SynthDef(\vrb_master, { |out=0, gate=1, inbus=0, drive=0.18, width=0.25, tremRate=0.0, tremDepth=0.0, output=0.9|
			var env, input, mid, side, widthCtl, trem, sig, driveCtl;
			widthCtl = width.clip(0, 1);
			env = EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate: gate, doneAction: 2);
			input = In.ar(inbus, 2);
			mid = (input[0] + input[1]) * 0.5;
			side = (input[0] - input[1]) * 0.5 * (1.0 + (widthCtl * 1.5));
			sig = [mid + side, mid - side];
			trem = SinOsc.kr(tremRate.clip(0.01, 12.0), 0, tremDepth.clip(0, 1) * 0.5, 1.0 - (tremDepth.clip(0, 1) * 0.5));
			sig = sig * trem;
			sig = CompanderD.ar(sig, 0.8, 1.0, 0.45, 0.01, 0.2);
			driveCtl = 1.0 + (drive.clip(0, 1) * 4.0);
			sig = (sig * driveCtl).tanh / driveCtl.sqrt;
			Out.ar(out, LeakDC.ar(sig * output.clip(0, 1) * env));
		}).add;

		s.sync;

		~fxBus = Bus.audio(s, 2);
		~aggroBus = Bus.audio(s, 2);
		~delayBus = Bus.audio(s, 2);
		~chorusBus = Bus.audio(s, 2);
		~verbBus = Bus.audio(s, 2);
		~masterBus = Bus.audio(s, 2);

		~bodyDetected = 0;
		~bodyTargetAmp = 0.0;
		~bodyParams = (
			freq: 220.0,
			amp: 0.0,
			cutoff: 1200.0,
			pan: 0.0
		);
		~bodyUi = (
			mode: 0.0,
			texture: 0.35,
			noiseMix: 0.18,
			subMix: 0.55,
			motion: 0.35,
			resonance: 0.22
		);
		~triggerUi = (
			onset: (mode: 0.0, color: 0.35),
			impact: (mode: 0.0, color: 0.45),
			enter: (mode: 0.0, color: 0.45),
			exit: (mode: 0.0, color: 0.35),
			flow: (mode: 0.0, color: 0.5)
		);
		~fxUi = (
			harshNoise: (enabled: 0, level: 0.0, tone: 0.62, hp: 1800.0, lp: 9800.0, duck: 0.22),
			highpass: (enabled: 0, freq: 120.0, resonance: 0.4, mix: 1.0),
			lowpass: (enabled: 0, freq: 9200.0, resonance: 0.45, mix: 1.0),
			distortion: (enabled: 0, drive: 0.0, mix: 0.0, fold: 0.0, bias: 0.0, tone: 0.68),
			glitch: (enabled: 0, mix: 0.0, rate: 8.0, depth: 0.0, crush: 0.0, gate: 0.0),
			delay: (time: 0.2, feedback: 0.25, mix: 0.32, tone: 0.62),
			chorus: (mix: 0.12, rate: 0.18, depth: 0.012),
			reverb: (mix: 0.18, room: 0.55, damp: 0.45, tone: 0.6),
			master: (drive: 0.18, width: 0.25, tremRate: 0.0, tremDepth: 0.0, output: 0.9)
		);

		~body = Synth.head(s, \vrb_body, [
			\out, ~fxBus.index,
			\freq, ~bodyParams[\freq],
			\amp, ~bodyParams[\amp],
			\cutoff, ~bodyParams[\cutoff],
			\pan, ~bodyParams[\pan],
			\mode, ~bodyUi[\mode],
			\texture, ~bodyUi[\texture],
			\noiseMix, ~bodyUi[\noiseMix],
			\subMix, ~bodyUi[\subMix],
			\motion, ~bodyUi[\motion],
			\resonance, ~bodyUi[\resonance]
		]);

		~aggro = Synth.new(\vrb_aggression, [
			\inbus, ~fxBus.index,
			\out, ~aggroBus.index,
			\harshOn, ~fxUi[\harshNoise][\enabled],
			\harshLevel, ~fxUi[\harshNoise][\level],
			\harshTone, ~fxUi[\harshNoise][\tone],
			\harshHp, ~fxUi[\harshNoise][\hp],
			\harshLp, ~fxUi[\harshNoise][\lp],
			\harshDuck, ~fxUi[\harshNoise][\duck],
			\hpOn, ~fxUi[\highpass][\enabled],
			\hpFreq, ~fxUi[\highpass][\freq],
			\hpRq, ~fxUi[\highpass][\resonance],
			\hpMix, ~fxUi[\highpass][\mix],
			\lpOn, ~fxUi[\lowpass][\enabled],
			\lpFreq, ~fxUi[\lowpass][\freq],
			\lpRq, ~fxUi[\lowpass][\resonance],
			\lpMix, ~fxUi[\lowpass][\mix],
			\distOn, ~fxUi[\distortion][\enabled],
			\distDrive, ~fxUi[\distortion][\drive],
			\distMix, ~fxUi[\distortion][\mix],
			\distFold, ~fxUi[\distortion][\fold],
			\distBias, ~fxUi[\distortion][\bias],
			\distTone, ~fxUi[\distortion][\tone],
			\glitchOn, ~fxUi[\glitch][\enabled],
			\glitchMix, ~fxUi[\glitch][\mix],
			\glitchRate, ~fxUi[\glitch][\rate],
			\glitchDepth, ~fxUi[\glitch][\depth],
			\glitchCrush, ~fxUi[\glitch][\crush],
			\glitchGate, ~fxUi[\glitch][\gate]
		], s, \addToTail);

		~delay = Synth.new(\vrb_delay, [
			\inbus, ~aggroBus.index,
			\out, ~delayBus.index,
			\delaytime, ~fxUi[\delay][\time],
			\feedback, ~fxUi[\delay][\feedback],
			\mix, ~fxUi[\delay][\mix],
			\tone, ~fxUi[\delay][\tone]
		], s, \addToTail);

		~chorus = Synth.new(\vrb_chorus, [
			\inbus, ~delayBus.index,
			\out, ~chorusBus.index,
			\mix, ~fxUi[\chorus][\mix],
			\rate, ~fxUi[\chorus][\rate],
			\depth, ~fxUi[\chorus][\depth]
		], s, \addToTail);

		~reverb = Synth.new(\vrb_reverb, [
			\inbus, ~chorusBus.index,
			\out, ~verbBus.index,
			\mix, ~fxUi[\reverb][\mix],
			\room, ~fxUi[\reverb][\room],
			\damp, ~fxUi[\reverb][\damp],
			\tone, ~fxUi[\reverb][\tone]
		], s, \addToTail);

		~master = Synth.new(\vrb_master, [
			\inbus, ~verbBus.index,
			\out, 0,
			\drive, ~fxUi[\master][\drive],
			\width, ~fxUi[\master][\width],
			\tremRate, ~fxUi[\master][\tremRate],
			\tremDepth, ~fxUi[\master][\tremDepth],
			\output, ~fxUi[\master][\output]
		], s, \addToTail);

		updateTriggerState = { |key, values|
			var state, mode, color;
			state = ~triggerUi[key];
			mode = values.at(\mode);
			color = values.at(\color);
			if(mode.notNil) { state[\mode] = mode.asFloat.clip(0, 3) };
			if(color.notNil) { state[\color] = color.asFloat.clip(0, 1) };
		};

		refreshFxState = {
			if(~aggro.notNil) {
				~aggro.set(
					\harshOn, ~fxUi[\harshNoise][\enabled],
					\harshLevel, ~fxUi[\harshNoise][\level],
					\harshTone, ~fxUi[\harshNoise][\tone],
					\harshHp, ~fxUi[\harshNoise][\hp],
					\harshLp, ~fxUi[\harshNoise][\lp],
					\harshDuck, ~fxUi[\harshNoise][\duck],
					\hpOn, ~fxUi[\highpass][\enabled],
					\hpFreq, ~fxUi[\highpass][\freq],
					\hpRq, ~fxUi[\highpass][\resonance],
					\hpMix, ~fxUi[\highpass][\mix],
					\lpOn, ~fxUi[\lowpass][\enabled],
					\lpFreq, ~fxUi[\lowpass][\freq],
					\lpRq, ~fxUi[\lowpass][\resonance],
					\lpMix, ~fxUi[\lowpass][\mix],
					\distOn, ~fxUi[\distortion][\enabled],
					\distDrive, ~fxUi[\distortion][\drive],
					\distMix, ~fxUi[\distortion][\mix],
					\distFold, ~fxUi[\distortion][\fold],
					\distBias, ~fxUi[\distortion][\bias],
					\distTone, ~fxUi[\distortion][\tone],
					\glitchOn, ~fxUi[\glitch][\enabled],
					\glitchMix, ~fxUi[\glitch][\mix],
					\glitchRate, ~fxUi[\glitch][\rate],
					\glitchDepth, ~fxUi[\glitch][\depth],
					\glitchCrush, ~fxUi[\glitch][\crush],
					\glitchGate, ~fxUi[\glitch][\gate]
				);
			};
			if(~delay.notNil) {
				~delay.set(
					\delaytime, ~fxUi[\delay][\time],
					\feedback, ~fxUi[\delay][\feedback],
					\mix, ~fxUi[\delay][\mix],
					\tone, ~fxUi[\delay][\tone]
				);
			};
			if(~chorus.notNil) {
				~chorus.set(
					\mix, ~fxUi[\chorus][\mix],
					\rate, ~fxUi[\chorus][\rate],
					\depth, ~fxUi[\chorus][\depth]
				);
			};
			if(~reverb.notNil) {
				~reverb.set(
					\mix, ~fxUi[\reverb][\mix],
					\room, ~fxUi[\reverb][\room],
					\damp, ~fxUi[\reverb][\damp],
					\tone, ~fxUi[\reverb][\tone]
				);
			};
			if(~master.notNil) {
				~master.set(
					\drive, ~fxUi[\master][\drive],
					\width, ~fxUi[\master][\width],
					\tremRate, ~fxUi[\master][\tremRate],
					\tremDepth, ~fxUi[\master][\tremDepth],
					\output, ~fxUi[\master][\output]
				);
			};
		};

		setBodyState = {
			var nextAmp;
			nextAmp = if(~bodyDetected > 0) { ~bodyTargetAmp } { 0.0 };
			if(~body.notNil) {
				~body.set(
					\freq, ~bodyParams[\freq],
					\amp, nextAmp.clip(0, 1),
					\cutoff, ~bodyParams[\cutoff],
					\pan, ~bodyParams[\pan],
					\mode, ~bodyUi[\mode],
					\texture, ~bodyUi[\texture],
					\noiseMix, ~bodyUi[\noiseMix],
					\subMix, ~bodyUi[\subMix],
					\motion, ~bodyUi[\motion],
					\resonance, ~bodyUi[\resonance]
				);
			};
		};

		updateDetected = { |value|
			~bodyDetected = value.asInteger.clip(0, 1);
			setBodyState.();
		};

		makeTrigger = { |name, key, defaults|
			{ |msg|
				var values, state, amp, freq, pan, mode, color;
				values = makeNamedValueParser.(msg);
				state = ~triggerUi[key];
				amp = values.at(\amp);
				freq = values.at(\freq);
				pan = values.at(\pan);
				mode = values.at(\mode);
				color = values.at(\color);
				if(amp.isNil) { amp = defaults[\amp] };
				if(freq.isNil) { freq = defaults[\freq] };
				if(pan.isNil) { pan = defaults[\pan] };
				if(mode.isNil) { mode = state[\mode] };
				if(color.isNil) { color = state[\color] };
				Synth(name, [
					\out, ~fxBus.index,
					\amp, amp.asFloat,
					\freq, freq.asFloat,
					\pan, pan.asFloat,
					\mode, mode.asFloat,
					\color, color.asFloat
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
			if(freq.notNil) { ~bodyParams[\freq] = freq.asFloat.clip(35, 2400) };
			if(amp.notNil) { ~bodyTargetAmp = amp.asFloat.clip(0, 1) };
			if(cutoff.notNil) { ~bodyParams[\cutoff] = cutoff.asFloat.clip(80, 10000) };
			if(pan.notNil) { ~bodyParams[\pan] = pan.asFloat.clip(-1, 1) };
			setBodyState.();
		}, '/synth/body', recvPort: NetAddr.langPort);

		OSCdef(\uiBody, { |msg|
			var values, mode, texture, noiseMix, subMix, motion, resonance;
			values = makeNamedValueParser.(msg);
			mode = values.at(\mode);
			texture = values.at(\texture);
			noiseMix = values.at(\noiseMix);
			subMix = values.at(\subMix);
			motion = values.at(\motion);
			resonance = values.at(\resonance);
			if(mode.notNil) { ~bodyUi[\mode] = mode.asFloat.clip(0, 3) };
			if(texture.notNil) { ~bodyUi[\texture] = texture.asFloat.clip(0, 1) };
			if(noiseMix.notNil) { ~bodyUi[\noiseMix] = noiseMix.asFloat.clip(0, 1) };
			if(subMix.notNil) { ~bodyUi[\subMix] = subMix.asFloat.clip(0, 1) };
			if(motion.notNil) { ~bodyUi[\motion] = motion.asFloat.clip(0, 1) };
			if(resonance.notNil) { ~bodyUi[\resonance] = resonance.asFloat.clip(0.08, 0.95) };
			setBodyState.();
		}, '/ui/body', recvPort: NetAddr.langPort);

		OSCdef(\reverbMix, { |msg|
			~fxUi[\reverb][\mix] = firstValue.(msg, ~fxUi[\reverb][\mix]).clip(0, 1);
			refreshFxState.();
		}, '/fx/reverb/mix', recvPort: NetAddr.langPort);

		OSCdef(\reverbRoom, { |msg|
			~fxUi[\reverb][\room] = firstValue.(msg, ~fxUi[\reverb][\room]).clip(0, 1);
			refreshFxState.();
		}, '/fx/reverb/room', recvPort: NetAddr.langPort);

		OSCdef(\delayTime, { |msg|
			~fxUi[\delay][\time] = firstValue.(msg, ~fxUi[\delay][\time]).clip(0.01, 0.95);
			refreshFxState.();
		}, '/fx/delay/time', recvPort: NetAddr.langPort);

		OSCdef(\delayFeedback, { |msg|
			~fxUi[\delay][\feedback] = firstValue.(msg, ~fxUi[\delay][\feedback]).clip(0.01, 0.99);
			refreshFxState.();
		}, '/fx/delay/feedback', recvPort: NetAddr.langPort);

		OSCdef(\uiDelay, { |msg|
			var values, time, feedback, mix, tone;
			values = makeNamedValueParser.(msg);
			time = values.at(\time);
			feedback = values.at(\feedback);
			mix = values.at(\mix);
			tone = values.at(\tone);
			if(time.notNil) { ~fxUi[\delay][\time] = time.asFloat.clip(0.01, 0.95) };
			if(feedback.notNil) { ~fxUi[\delay][\feedback] = feedback.asFloat.clip(0.01, 0.99) };
			if(mix.notNil) { ~fxUi[\delay][\mix] = mix.asFloat.clip(0, 1) };
			if(tone.notNil) { ~fxUi[\delay][\tone] = tone.asFloat.clip(0, 1) };
			refreshFxState.();
		}, '/ui/fx/delay', recvPort: NetAddr.langPort);

		OSCdef(\uiHarshNoise, { |msg|
			var values, enabled, level, tone, hp, lp, duck;
			values = makeNamedValueParser.(msg);
			enabled = values.at(\enabled);
			level = values.at(\level);
			tone = values.at(\tone);
			hp = values.at(\hp);
			lp = values.at(\lp);
			duck = values.at(\duck);
			if(enabled.notNil) { ~fxUi[\harshNoise][\enabled] = enabled.asFloat.clip(0, 1) };
			if(level.notNil) { ~fxUi[\harshNoise][\level] = level.asFloat.clip(0, 1) };
			if(tone.notNil) { ~fxUi[\harshNoise][\tone] = tone.asFloat.clip(0, 1) };
			if(hp.notNil) { ~fxUi[\harshNoise][\hp] = hp.asFloat.clip(120, 12000) };
			if(lp.notNil) { ~fxUi[\harshNoise][\lp] = lp.asFloat.clip(1200, 18000) };
			if(duck.notNil) { ~fxUi[\harshNoise][\duck] = duck.asFloat.clip(0, 1) };
			refreshFxState.();
		}, '/ui/fx/harshNoise', recvPort: NetAddr.langPort);

		OSCdef(\uiHighpass, { |msg|
			var values, enabled, freq, resonance, mix;
			values = makeNamedValueParser.(msg);
			enabled = values.at(\enabled);
			freq = values.at(\freq);
			resonance = values.at(\resonance);
			mix = values.at(\mix);
			if(enabled.notNil) { ~fxUi[\highpass][\enabled] = enabled.asFloat.clip(0, 1) };
			if(freq.notNil) { ~fxUi[\highpass][\freq] = freq.asFloat.clip(20, 12000) };
			if(resonance.notNil) { ~fxUi[\highpass][\resonance] = resonance.asFloat.clip(0.08, 0.95) };
			if(mix.notNil) { ~fxUi[\highpass][\mix] = mix.asFloat.clip(0, 1) };
			refreshFxState.();
		}, '/ui/fx/highpass', recvPort: NetAddr.langPort);

		OSCdef(\uiLowpass, { |msg|
			var values, enabled, freq, resonance, mix;
			values = makeNamedValueParser.(msg);
			enabled = values.at(\enabled);
			freq = values.at(\freq);
			resonance = values.at(\resonance);
			mix = values.at(\mix);
			if(enabled.notNil) { ~fxUi[\lowpass][\enabled] = enabled.asFloat.clip(0, 1) };
			if(freq.notNil) { ~fxUi[\lowpass][\freq] = freq.asFloat.clip(120, 18000) };
			if(resonance.notNil) { ~fxUi[\lowpass][\resonance] = resonance.asFloat.clip(0.08, 0.95) };
			if(mix.notNil) { ~fxUi[\lowpass][\mix] = mix.asFloat.clip(0, 1) };
			refreshFxState.();
		}, '/ui/fx/lowpass', recvPort: NetAddr.langPort);

		OSCdef(\uiDistortion, { |msg|
			var values, enabled, drive, mix, fold, bias, tone;
			values = makeNamedValueParser.(msg);
			enabled = values.at(\enabled);
			drive = values.at(\drive);
			mix = values.at(\mix);
			fold = values.at(\fold);
			bias = values.at(\bias);
			tone = values.at(\tone);
			if(enabled.notNil) { ~fxUi[\distortion][\enabled] = enabled.asFloat.clip(0, 1) };
			if(drive.notNil) { ~fxUi[\distortion][\drive] = drive.asFloat.clip(0, 1) };
			if(mix.notNil) { ~fxUi[\distortion][\mix] = mix.asFloat.clip(0, 1) };
			if(fold.notNil) { ~fxUi[\distortion][\fold] = fold.asFloat.clip(0, 1) };
			if(bias.notNil) { ~fxUi[\distortion][\bias] = bias.asFloat.clip(-1, 1) };
			if(tone.notNil) { ~fxUi[\distortion][\tone] = tone.asFloat.clip(0, 1) };
			refreshFxState.();
		}, '/ui/fx/distortion', recvPort: NetAddr.langPort);

		OSCdef(\uiGlitch, { |msg|
			var values, enabled, mix, rate, depth, crush, gate;
			values = makeNamedValueParser.(msg);
			enabled = values.at(\enabled);
			mix = values.at(\mix);
			rate = values.at(\rate);
			depth = values.at(\depth);
			crush = values.at(\crush);
			gate = values.at(\gate);
			if(enabled.notNil) { ~fxUi[\glitch][\enabled] = enabled.asFloat.clip(0, 1) };
			if(mix.notNil) { ~fxUi[\glitch][\mix] = mix.asFloat.clip(0, 1) };
			if(rate.notNil) { ~fxUi[\glitch][\rate] = rate.asFloat.clip(0.25, 40.0) };
			if(depth.notNil) { ~fxUi[\glitch][\depth] = depth.asFloat.clip(0, 1) };
			if(crush.notNil) { ~fxUi[\glitch][\crush] = crush.asFloat.clip(0, 1) };
			if(gate.notNil) { ~fxUi[\glitch][\gate] = gate.asFloat.clip(0, 1) };
			refreshFxState.();
		}, '/ui/fx/glitch', recvPort: NetAddr.langPort);

		OSCdef(\uiChorus, { |msg|
			var values, mix, rate, depth;
			values = makeNamedValueParser.(msg);
			mix = values.at(\mix);
			rate = values.at(\rate);
			depth = values.at(\depth);
			if(mix.notNil) { ~fxUi[\chorus][\mix] = mix.asFloat.clip(0, 1) };
			if(rate.notNil) { ~fxUi[\chorus][\rate] = rate.asFloat.clip(0.02, 8.0) };
			if(depth.notNil) { ~fxUi[\chorus][\depth] = depth.asFloat.clip(0.0001, 0.05) };
			refreshFxState.();
		}, '/ui/fx/chorus', recvPort: NetAddr.langPort);

		OSCdef(\uiReverb, { |msg|
			var values, mix, room, damp, tone;
			values = makeNamedValueParser.(msg);
			mix = values.at(\mix);
			room = values.at(\room);
			damp = values.at(\damp);
			tone = values.at(\tone);
			if(mix.notNil) { ~fxUi[\reverb][\mix] = mix.asFloat.clip(0, 1) };
			if(room.notNil) { ~fxUi[\reverb][\room] = room.asFloat.clip(0, 1) };
			if(damp.notNil) { ~fxUi[\reverb][\damp] = damp.asFloat.clip(0, 1) };
			if(tone.notNil) { ~fxUi[\reverb][\tone] = tone.asFloat.clip(0, 1) };
			refreshFxState.();
		}, '/ui/fx/reverb', recvPort: NetAddr.langPort);

		OSCdef(\uiMaster, { |msg|
			var values, drive, width, tremRate, tremDepth, output;
			values = makeNamedValueParser.(msg);
			drive = values.at(\drive);
			width = values.at(\width);
			tremRate = values.at(\tremRate);
			tremDepth = values.at(\tremDepth);
			output = values.at(\output);
			if(drive.notNil) { ~fxUi[\master][\drive] = drive.asFloat.clip(0, 1) };
			if(width.notNil) { ~fxUi[\master][\width] = width.asFloat.clip(0, 1) };
			if(tremRate.notNil) { ~fxUi[\master][\tremRate] = tremRate.asFloat.clip(0, 12) };
			if(tremDepth.notNil) { ~fxUi[\master][\tremDepth] = tremDepth.asFloat.clip(0, 1) };
			if(output.notNil) { ~fxUi[\master][\output] = output.asFloat.clip(0, 1) };
			refreshFxState.();
		}, '/ui/master', recvPort: NetAddr.langPort);

		OSCdef(\uiTriggerOnset, { |msg|
			updateTriggerState.(\onset, makeNamedValueParser.(msg));
		}, '/ui/trigger/onset', recvPort: NetAddr.langPort);

		OSCdef(\uiTriggerImpact, { |msg|
			updateTriggerState.(\impact, makeNamedValueParser.(msg));
		}, '/ui/trigger/impact', recvPort: NetAddr.langPort);

		OSCdef(\uiTriggerEnter, { |msg|
			updateTriggerState.(\enter, makeNamedValueParser.(msg));
		}, '/ui/trigger/enter', recvPort: NetAddr.langPort);

		OSCdef(\uiTriggerExit, { |msg|
			updateTriggerState.(\exit, makeNamedValueParser.(msg));
		}, '/ui/trigger/exit', recvPort: NetAddr.langPort);

		OSCdef(\uiTriggerFlow, { |msg|
			updateTriggerState.(\flow, makeNamedValueParser.(msg));
		}, '/ui/trigger/flow', recvPort: NetAddr.langPort);

		OSCdef(\motionOnset, makeTrigger.(\vrb_onset, \onset, (amp: 0.4, freq: 440, pan: 0.0)), '/trigger/motion_onset', recvPort: NetAddr.langPort);
		OSCdef(\impact, makeTrigger.(\vrb_impact, \impact, (amp: 0.5, freq: 180, pan: 0.0)), '/trigger/impact', recvPort: NetAddr.langPort);
		OSCdef(\flowBurst, makeTrigger.(\vrb_flow_burst, \flow, (amp: 0.4, freq: 900, pan: 0.0)), '/trigger/flow_burst', recvPort: NetAddr.langPort);

		OSCdef(\personEnter, { |msg|
			var values, state, amp, freq, pan, mode, color;
			values = makeNamedValueParser.(msg);
			state = ~triggerUi[\enter];
			amp = values.at(\amp);
			freq = values.at(\freq);
			pan = values.at(\pan);
			mode = values.at(\mode);
			color = values.at(\color);
			if(amp.isNil) { amp = 0.45 };
			if(freq.isNil) { freq = 320 };
			if(pan.isNil) { pan = 0.0 };
			if(mode.isNil) { mode = state[\mode] };
			if(color.isNil) { color = state[\color] };
			Synth(\vrb_enter, [
				\out, ~fxBus.index,
				\amp, amp.asFloat,
				\freq, freq.asFloat,
				\pan, pan.asFloat,
				\mode, mode.asFloat,
				\color, color.asFloat
			]);
			~bodyParams[\freq] = freq.asFloat.clip(35, 2400);
			~bodyParams[\pan] = pan.asFloat.clip(-1, 1);
			~bodyTargetAmp = amp.asFloat.clip(0, 1);
			updateDetected.(1);
		}, '/trigger/person_enter', recvPort: NetAddr.langPort);

		OSCdef(\personExit, { |msg|
			var values, state, amp, freq, pan, mode, color;
			values = makeNamedValueParser.(msg);
			state = ~triggerUi[\exit];
			amp = values.at(\amp);
			freq = values.at(\freq);
			pan = values.at(\pan);
			mode = values.at(\mode);
			color = values.at(\color);
			if(amp.isNil) { amp = 0.35 };
			if(freq.isNil) { freq = 180 };
			if(pan.isNil) { pan = 0.0 };
			if(mode.isNil) { mode = state[\mode] };
			if(color.isNil) { color = state[\color] };
			Synth(\vrb_exit, [
				\out, ~fxBus.index,
				\amp, amp.asFloat,
				\freq, freq.asFloat,
				\pan, pan.asFloat,
				\mode, mode.asFloat,
				\color, color.asFloat
			]);
			~bodyParams[\pan] = pan.asFloat.clip(-1, 1);
			updateDetected.(0);
		}, '/trigger/person_exit', recvPort: NetAddr.langPort);

		OSCdef(\detected, { |msg|
			updateDetected.(firstValue.(msg, 0).asInteger);
		}, '/vrb/meta/detected', recvPort: NetAddr.langPort);

		~vrbCleanup = {
			if(OSCdef(\body).notNil) { OSCdef(\body).free };
			if(OSCdef(\uiBody).notNil) { OSCdef(\uiBody).free };
			if(OSCdef(\reverbMix).notNil) { OSCdef(\reverbMix).free };
			if(OSCdef(\reverbRoom).notNil) { OSCdef(\reverbRoom).free };
			if(OSCdef(\delayTime).notNil) { OSCdef(\delayTime).free };
			if(OSCdef(\delayFeedback).notNil) { OSCdef(\delayFeedback).free };
			if(OSCdef(\uiHarshNoise).notNil) { OSCdef(\uiHarshNoise).free };
			if(OSCdef(\uiHighpass).notNil) { OSCdef(\uiHighpass).free };
			if(OSCdef(\uiLowpass).notNil) { OSCdef(\uiLowpass).free };
			if(OSCdef(\uiDistortion).notNil) { OSCdef(\uiDistortion).free };
			if(OSCdef(\uiGlitch).notNil) { OSCdef(\uiGlitch).free };
			if(OSCdef(\uiDelay).notNil) { OSCdef(\uiDelay).free };
			if(OSCdef(\uiChorus).notNil) { OSCdef(\uiChorus).free };
			if(OSCdef(\uiReverb).notNil) { OSCdef(\uiReverb).free };
			if(OSCdef(\uiMaster).notNil) { OSCdef(\uiMaster).free };
			if(OSCdef(\uiTriggerOnset).notNil) { OSCdef(\uiTriggerOnset).free };
			if(OSCdef(\uiTriggerImpact).notNil) { OSCdef(\uiTriggerImpact).free };
			if(OSCdef(\uiTriggerEnter).notNil) { OSCdef(\uiTriggerEnter).free };
			if(OSCdef(\uiTriggerExit).notNil) { OSCdef(\uiTriggerExit).free };
			if(OSCdef(\uiTriggerFlow).notNil) { OSCdef(\uiTriggerFlow).free };
			if(OSCdef(\motionOnset).notNil) { OSCdef(\motionOnset).free };
			if(OSCdef(\impact).notNil) { OSCdef(\impact).free };
			if(OSCdef(\personEnter).notNil) { OSCdef(\personEnter).free };
			if(OSCdef(\personExit).notNil) { OSCdef(\personExit).free };
			if(OSCdef(\flowBurst).notNil) { OSCdef(\flowBurst).free };
			if(OSCdef(\detected).notNil) { OSCdef(\detected).free };
			if(~body.notNil) { ~body.set(\gate, 0) };
			if(~aggro.notNil) { ~aggro.set(\gate, 0) };
			if(~delay.notNil) { ~delay.set(\gate, 0) };
			if(~chorus.notNil) { ~chorus.set(\gate, 0) };
			if(~reverb.notNil) { ~reverb.set(\gate, 0) };
			if(~master.notNil) { ~master.set(\gate, 0) };
			if(~masterBus.notNil) { ~masterBus.free };
			if(~verbBus.notNil) { ~verbBus.free };
			if(~chorusBus.notNil) { ~chorusBus.free };
			if(~delayBus.notNil) { ~delayBus.free };
			if(~aggroBus.notNil) { ~aggroBus.free };
			if(~fxBus.notNil) { ~fxBus.free };
		};

		refreshFxState.();
		setBodyState.();
		"virtual-real-body: OSCdefs registered".postln;
	};
}.value;
