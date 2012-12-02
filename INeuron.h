/**
 * \file INeuron.h
 *
 * Header file for INeuron
 * INeuron is the base interface for a Neuron to be used with the Simulator.
 *
	DATE		VERSION		NAME		COMMENT
 *	11/24/2012	1.0			dwise		Initial stab at creating an INeuron in the simulator
 */

#pragma once

#ifndef _INEURON_H_
#define _INEURON_H_

#include "global.h"

//! Abstract interface class to provide basic framework needed for a Neuron to function with the simulator
class INeuron {
public:
	//! A boolean which tracks whether the neuron has fired
	bool hasFired;

	//! The length of the absolute refractory period. [units=sec; range=(0,1);]
	FLOAT Trefract;

	//! If \f$V_m\f$ exceeds \f$V_{thresh}\f$ a spike is emmited. [units=V; range=(-10,100);]
	FLOAT Vthresh;

	//! The resting membrane voltage. [units=V; range=(-1,1);]
	FLOAT Vrest;

	//! The voltage to reset \f$V_m\f$ to after a spike. [units=V; range=(-1,1);]
	FLOAT Vreset;

	//! The initial condition for \f$V_m\f$ at time \f$t=0\f$. [units=V; range=(-1,1);]
	FLOAT Vinit;
	
	//! Constructor.
	INeuron();
	virtual ~INeuron();

	//! Set the neuron parameters.
	virtual void setParams(FLOAT new_Iinject, FLOAT new_Inoise, FLOAT new_Vthresh, FLOAT new_Vresting,
			FLOAT new_Vreset, FLOAT new_Vinit, FLOAT new_deltaT);

	//! Process another time step.
	virtual void advance(FLOAT& summationPoint) = 0;

	//! Emit a spike.
	virtual void fire() = 0;

	//! Update internal constants.
	virtual void updateInternal() = 0;

	//! Reset to initial state.
	virtual void reset();

	//! Return a terse representation.
	virtual string toString();

	//! Return a string with the Vm.
	virtual string toStringVm();

	//! Return the complete state of the neuron.
	virtual string toStringAll();

	//! Return refractory state.
	virtual bool isRefractory();

	#ifdef STORE_SPIKEHISTORY

	//! The history of spike times.
	virtual vector <uint64_t> spikeHistory;

	//! Return the number of spikes emitted.
	virtual int nSpikes();

	//! Returns a pointer to a vector of spike times
	virtual vector<uint64_t>* getSpikes();

	//! Return the count of spikes that occur at or after begin_time
	virtual int nSpikesSince(uint64_t begin_step);

	#endif // STORE_SPIKEHISTORY

	//! Clear the spike count
	virtual void clearSpikeCount();

	//! Return the spike count
	virtual int getSpikeCount();

	//! Write the neuron data to the stream
	virtual void write(ostream& os);

	//! Read the neuron data from the stream
	virtual void read(istream& is);

protected:
	//! The simulation time step size.
	FLOAT deltaT;

	//! The membrane capacity \f$C_m\f$ [range=(0,1); units=F;]
	FLOAT Cm;

	//! The membrane resistance \f$R_m\f$ [units=Ohm; range=(0,1e30)]
	FLOAT Rm;

	//! The standard deviation of the noise to be added each integration time constant. [range=(0,1); units=A;]
	FLOAT Inoise;

	//! A constant current to be injected into the LIF neuron. [units=A; range=(-1,1);]
	FLOAT Iinject;

	//! The synaptic input current.
	FLOAT Isyn;

	//! The remaining number of time steps for the absolute refractory period.
	int nStepsInRefr;

	//! Internal constant for the exponential Euler integration of \f$V_m\f$.
	FLOAT C1;
	//! Internal constant for the exponential Euler integration of \f$V_m\f$.
	FLOAT C2;
	//! Internal constant for the exponential Euler integration of \f$V_m\f$.
	FLOAT I0;

	//! The membrane voltage \f$V_m\f$ [readonly; units=V;]
	FLOAT Vm;

	//! The membrane time constant \f$(R_m \cdot C_m)\f$
	FLOAT Tau;

	//! The number of spikes since the last growth cycle
	int spikeCount;
};

#endif

