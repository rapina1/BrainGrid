/**
 *      @file AllSpikingNeurons.h
 *
 *      @brief A container of all spiking neuron data
 */

#pragma once

using namespace std;

#include "Global.h"
#include "SimulationInfo.h"
#include "AllNeurons.h"

class AllSpikingNeurons : public AllNeurons
{
    public:
        /*! A boolean which tracks whether the neuron has fired
         *  
         *  Usage: LOCAL VARIABLE
         *  - AllIFNeurons::AllIFNeurons() --- Initialized
         *  - LIFModel::readNeuron() --- Modified
         *  - LIFModel::writeNeuron() --- Accessed
         *  - SingleThreadedSpikingModel::advanceNeurons() --- Accessed & Modified
         *  - SingleThreadedSpikingModel::fire() --- Modified
         *  - GpuSim_struct.cu::advanceNeuronsDevice() --- Modified
         */
        bool *hasFired;

        /*! The number of spikes since the last growth cycle
         *  
         *  Usage: LOCAL VARIABLE
         *  - AllIFNeurons::AllIFNeurons() --- Initialized
         *  - LIFModel::updateHistory() --- Accessed
         *  - LIFModel::clearSpikeCounts() --- Modified
         *  - SingleThreadedSpikingModel::fire() --- Modified
         *  - GpuSim_struct.cu::clearSpikeCounts() --- Modified
         *  - GPUSpikingModel::copyDeviceSpikeCountsToHost() --- Accessed
         *  - GpuSim_struct.cu::advanceNeuronsDevice() --- Modified
         *  - Hdf5Recorder::compileHistories() --- Accessed
         *  - XmlRecorder::compileHistories() --- Accessed
         */
        int *spikeCount;

        int *spikeCountOffset;

        /*! Step count for each spike fired by each neuron
         *
         *  Usage: LOCAL VARIABLE
         *  - LIFModel::createAllNeurons() --- Initialized
         *  - SingleThreadedSpikingModel::fire() --- Modified
         *  - GpuSim_struct.cu::advanceNeuronsDevice() --- Modified
         *  - GPUSpikingModel::copyDeviceSpikeHistoryToHost() --- Accessed
         *  - Hdf5Recorder::compileHistories() --- Accessed
         *  - XmlRecorder::compileHistories() --- Accessed
         */
        uint64_t **spike_history;

        AllSpikingNeurons();
        virtual ~AllSpikingNeurons();

        virtual void setupNeurons(SimulationInfo *sim_info);
        virtual void cleanupNeurons(); 
        virtual int numParameters() = 0;
        virtual bool readParameters(const TiXmlElement& element) = 0;
        virtual void printParameters(ostream &output) const = 0;
        virtual void createAllNeurons(SimulationInfo *sim_info, Layout *layout) = 0;
        virtual string toString(const int i) const = 0;
        virtual void readNeurons(istream &input, const SimulationInfo *sim_info) = 0;
        virtual void writeNeurons(ostream& output, const SimulationInfo *sim_info) const = 0;
        void clearSpikeCounts(const SimulationInfo *sim_info);

#if defined(USE_GPU)
        virtual void allocNeuronDeviceStruct( void** allNeuronsDevice, SimulationInfo *sim_info ) = 0;
        virtual void deleteNeuronDeviceStruct( void* allNeuronsDevice, const SimulationInfo *sim_info ) = 0;
        virtual void copyNeuronHostToDevice( void* allNeuronsDevice, const SimulationInfo *sim_info ) = 0;
        virtual void copyNeuronDeviceToHost( void* allNeuronsDevice, const SimulationInfo *sim_info ) = 0;
        virtual void copyNeuronDeviceSpikeHistoryToHost( void* allNeuronsDevice, const SimulationInfo *sim_info ) = 0;
        virtual void copyNeuronDeviceSpikeCountsToHost( void* allNeuronsDevice, const SimulationInfo *sim_info ) = 0;
        virtual void clearNeuronSpikeCounts( void* allNeuronsDevice, const SimulationInfo *sim_info ) = 0;

    protected:
        void copyDeviceSpikeHistoryToHost( AllSpikingNeurons& allNeurons, const SimulationInfo *sim_info );
        void copyDeviceSpikeCountsToHost( AllSpikingNeurons& allNeurons, const SimulationInfo *sim_info );
        void clearDeviceSpikeCounts( AllSpikingNeurons& allNeurons, const SimulationInfo *sim_info );

        // Update the state of all neurons for a time step
        virtual void advanceNeurons(AllSynapses &synapses, AllNeurons* allNeuronsDevice, AllSynapses* allSynapsesDevice, const SimulationInfo *sim_info, float* randNoise, SynapseIndexMap* synapseIndexMapDevice) = 0;

    public:
        // set some parameters used for advanceNeuronsDevice
        virtual void setAdvanceNeuronsDeviceParams(AllSynapses &synapses);

#else
        // Update the state of all neurons for a time step
        virtual void advanceNeurons(AllSynapses &synapses, const SimulationInfo *sim_info, const SynapseIndexMap *synapseIndexMap);

        // Helper for #advanceNeuron. Updates state of a single neuron.
        virtual void advanceNeuron(const int index, const SimulationInfo *sim_info) = 0;

        // Initiates a firing of a neuron to connected neurons
        virtual void fire(const int index, const SimulationInfo *sim_info) const;

    public:
        uint64_t getSpikeHistory(int index, int offIndex, const SimulationInfo *sim_info);
#endif // defined(USE_GPU)

    protected:
        // parameters used for advanceNeuronsDevice
        bool m_fAllowBackPropagation;
        unsigned long long m_fpPreSpikeHit_h;
        unsigned long long m_fpPostSpikeHit_h;

    private:
        void freeResources();
};
