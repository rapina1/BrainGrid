/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - **\ 
 * @authors Aaron Oziel, Sean Blackbourn 
 *
 * Fumitaka Kawasaki (5/3/14):
 * All functions were completed and working. Therefore, the followng comments
 * were removed. 
 *
 * Aaron Wrote (2/3/14):
 * All comments are now tracking progress in conversion from old GpuSim_struct.cu
 * file to the new one here. This is a quick key to keep track of their meanings. 
 *
 *	TODO = 	Needs work and/or is blank. Used to indicate possibly problematic 
 *				functions. 
 *	DONE = 	Likely complete functions. Will still need to be checked for
 *				variable continuity and proper arguments. 
 *   REMOVED =	Deleted, likely due to it becoming unnecessary or not necessary 
 *				for GPU implementation. These functions will likely have to be 
 *				removed from the Model super class.
 *    COPIED = 	These functions were in the original GpuSim_struct.cu file 
 *				and were directly copy-pasted across to this file. 
 *
\** - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - **/

#include "GPUSpikingModel.h"

#ifdef PERFORMANCE_METRICS
float g_time;
cudaEvent_t start, stop;
#endif // PERFORMANCE_METRICS

__constant__ int d_debug_mask[1];

// ----------------------------------------------------------------------------

GPUSpikingModel::GPUSpikingModel(Connections *conns, IAllNeurons *neurons, IAllSynapses *synapses, Layout *layout) : 	
	Model::Model(conns, neurons, synapses, layout),
	synapseIndexMapDevice(NULL),
	randNoise_d(NULL),
	m_allNeuronsDevice(NULL),
	m_allSynapsesDevice(NULL)
{
}

GPUSpikingModel::~GPUSpikingModel() 
{
	//Let Model base class handle de-allocation
}

/*
 * Allocates and initializes memories on CUDA device.
 *
 * @param[out] allNeuronsDevice          Memory loation of the pointer to the neurons list on device memory.
 * @param[out] allSynapsesDevice         Memory loation of the pointer to the synapses list on device memory.
 * @param[in]  sim_info			Pointer to the simulation information.
 */
void GPUSpikingModel::allocDeviceStruct(void** allNeuronsDevice, void** allSynapsesDevice, SimulationInfo *sim_info)
{
	// Allocate Neurons and Synapses strucs on GPU device memory
	m_neurons->allocNeuronDeviceStruct( allNeuronsDevice, sim_info );
	m_synapses->allocSynapseDeviceStruct( allSynapsesDevice, sim_info );

	// Allocate memory for random noise array
	int neuron_count = sim_info->totalNeurons;
	BGSIZE randNoise_d_size = neuron_count * sizeof (float);	// size of random noise array
	checkCudaErrors( cudaMalloc ( ( void ** ) &randNoise_d, randNoise_d_size ) );

	// Copy host neuron and synapse arrays into GPU device
	m_neurons->copyNeuronHostToDevice( *allNeuronsDevice, sim_info );
	m_synapses->copySynapseHostToDevice( *allSynapsesDevice, sim_info );

	// allocate synapse inverse map in device memory
	allocSynapseImap( neuron_count );

        // copy inverse map to the device memory
        copySynapseIndexMapHostToDevice(*m_synapseIndexMap, sim_info->totalNeurons);
}

/*
 * Copies device memories to host memories and deallocaes them.
 *
 * @param[out] allNeuronsDevice          Memory loation of the pointer to the neurons list on device memory.
 * @param[out] allSynapsesDevice         Memory loation of the pointer to the synapses list on device memory.
 * @param[in]  sim_info                  Pointer to the simulation information.
 */
void GPUSpikingModel::deleteDeviceStruct(void** allNeuronsDevice, void** allSynapsesDevice, SimulationInfo *sim_info)
{
    // copy device synapse and neuron structs to host memory
    m_neurons->copyNeuronDeviceToHost( *allNeuronsDevice, sim_info );

    // Deallocate device memory
    m_neurons->deleteNeuronDeviceStruct( *allNeuronsDevice, sim_info );

    // copy device synapse and neuron structs to host memory
    m_synapses->copySynapseDeviceToHost( *allSynapsesDevice, sim_info );

    // Deallocate device memory
    m_synapses->deleteSynapseDeviceStruct( *allSynapsesDevice );

    deleteSynapseImap();

    checkCudaErrors( cudaFree( randNoise_d ) );
}

/*
 *  Sets up the Simulation.
 *
 *  @param  sim_info    SimulationInfo class to read information from.
 */
void GPUSpikingModel::setupSim(SimulationInfo *sim_info)
{
    // Set device ID
    checkCudaErrors( cudaSetDevice( g_deviceId ) );

    // Set DEBUG flag
    checkCudaErrors( cudaMemcpyToSymbol (d_debug_mask, &g_debug_mask, sizeof(int) ) );

    Model::setupSim(sim_info);

    //initialize Mersenne Twister
    //assuming neuron_count >= 100 and is a multiple of 100. Note rng_mt_rng_count must be <= MT_RNG_COUNT
    int rng_blocks = 25; //# of blocks the kernel will use
    int rng_nPerRng = 4; //# of iterations per thread (thread granularity, # of rands generated per thread)
    int rng_mt_rng_count = sim_info->totalNeurons/rng_nPerRng; //# of threads to generate for neuron_count rand #s
    int rng_threads = rng_mt_rng_count/rng_blocks; //# threads per block needed
    initMTGPU(sim_info->seed, rng_blocks, rng_threads, rng_nPerRng, rng_mt_rng_count);

#ifdef PERFORMANCE_METRICS
    cudaEventCreate( &start );
    cudaEventCreate( &stop );

    t_gpu_rndGeneration = 0.0f;
    t_gpu_advanceNeurons = 0.0f;
    t_gpu_advanceSynapses = 0.0f;
    t_gpu_calcSummation = 0.0f;
#endif // PERFORMANCE_METRICS

    // allocates memories on CUDA device
    allocDeviceStruct((void **)&m_allNeuronsDevice, (void **)&m_allSynapsesDevice, sim_info);

    // set some parameters used for advanceNeuronsDevice
    m_neurons->setAdvanceNeuronsDeviceParams(*m_synapses);

    // set some parameters used for advanceSynapsesDevice
    m_synapses->setAdvanceSynapsesDeviceParams();
}

/* 
 *  Begin terminating the simulator.
 *
 *  @param  sim_info    SimulationInfo to refer.
 */
void GPUSpikingModel::cleanupSim(SimulationInfo *sim_info)
{
    // deallocates memories on CUDA device
    deleteDeviceStruct((void**)&m_allNeuronsDevice, (void**)&m_allSynapsesDevice, sim_info);

#ifdef PERFORMANCE_METRICS
    cudaEventDestroy( start );
    cudaEventDestroy( stop );
#endif // PERFORMANCE_METRICS
}

/*
 *  Loads the simulation based on istream input.
 *
 *  @param  input   istream to read from.
 *  @param  sim_info    used as a reference to set info for neurons and synapses.
 */
void GPUSpikingModel::deserialize(istream& input, const SimulationInfo *sim_info)
{
    Model::deserialize(input, sim_info);

    // copy inverse map to the device memory
    copySynapseIndexMapHostToDevice(*m_synapseIndexMap, sim_info->totalNeurons);

    // Reinitialize device struct - Copy host neuron and synapse arrays into GPU device
    m_neurons->copyNeuronHostToDevice( m_allNeuronsDevice, sim_info );
    m_synapses->copySynapseHostToDevice( m_allSynapsesDevice, sim_info );
}

/* 
 *  Advance everything in the model one time step. In this case, that
 *  means calling all of the kernels that do the "micro step" updating
 *  (i.e., NOT the stuff associated with growth).
 *
 *  @param  sim_info    SimulationInfo class to read information from.
 */
void GPUSpikingModel::advance(const SimulationInfo *sim_info)
{
#ifdef PERFORMANCE_METRICS
	startTimer();
#endif // PERFORMANCE_METRICS

	normalMTGPU(randNoise_d);

#ifdef PERFORMANCE_METRICS
	lapTime(t_gpu_rndGeneration);
	startTimer();
#endif // PERFORMANCE_METRICS

	// display running info to console
	// Advance neurons ------------->
	m_neurons->advanceNeurons(*m_synapses, m_allNeuronsDevice, m_allSynapsesDevice, sim_info, randNoise_d, synapseIndexMapDevice);

#ifdef PERFORMANCE_METRICS
	lapTime(t_gpu_advanceNeurons);
	startTimer();
#endif // PERFORMANCE_METRICS

	// Advance synapses ------------->
	m_synapses->advanceSynapses(m_allSynapsesDevice, m_allNeuronsDevice, synapseIndexMapDevice, sim_info);

#ifdef PERFORMANCE_METRICS
	lapTime(t_gpu_advanceSynapses);
	startTimer();
#endif // PERFORMANCE_METRICS

	// calculate summation point
        calcSummationMap(sim_info);

#ifdef PERFORMANCE_METRICS
	lapTime(t_gpu_calcSummation);
#endif // PERFORMANCE_METRICS
}

/*
 * Add psr of all incoming synapses to summation points.
 *
 * @param[in] sim_info                   Pointer to the simulation information.
 */
void GPUSpikingModel::calcSummationMap(const SimulationInfo *sim_info)
{
    // CUDA parameters
    const int threadsPerBlock = 256;
    int blocksPerGrid = ( sim_info->totalNeurons + threadsPerBlock - 1 ) / threadsPerBlock;

    calcSummationMapDevice <<< blocksPerGrid, threadsPerBlock >>> ( sim_info->totalNeurons, m_allNeuronsDevice, synapseIndexMapDevice, m_allSynapsesDevice );
}

/* 
 *  Update the connection of all the Neurons and Synapses of the simulation.
 *
 *  @param  sim_info    SimulationInfo class to read information from.
 */
void GPUSpikingModel::updateConnections(const SimulationInfo *sim_info)
{
        dynamic_cast<AllSpikingNeurons*>(m_neurons)->copyNeuronDeviceSpikeCountsToHost(m_allNeuronsDevice, sim_info);
        dynamic_cast<AllSpikingNeurons*>(m_neurons)->copyNeuronDeviceSpikeHistoryToHost(m_allNeuronsDevice, sim_info);

        // Update Connections data
        if (m_conns->updateConnections(*m_neurons, sim_info, m_layout)) {
	    m_conns->updateSynapsesWeights(sim_info->totalNeurons, *m_neurons, *m_synapses, sim_info, m_allNeuronsDevice, m_allSynapsesDevice, m_layout);
            // create synapse inverse map
            m_synapses->createSynapseImap(m_synapseIndexMap, sim_info);
            // copy inverse map to the device memory
            copySynapseIndexMapHostToDevice(*m_synapseIndexMap, sim_info->totalNeurons);
        }
}

/*
 *  Update the Neuron's history.
 *
 *  @param  sim_info    SimulationInfo to refer from.
 */
void GPUSpikingModel::updateHistory(const SimulationInfo *sim_info)
{
    Model::updateHistory(sim_info);

    // clear spike count
    dynamic_cast<AllSpikingNeurons*>(m_neurons)->clearNeuronSpikeCounts(m_allNeuronsDevice, sim_info);
}

/* ------------------*\
|* # Helper Functions
\* ------------------*/

/*
 *  Allocate device memory for synapse inverse map.
 *  @param  count	The number of neurons.
 */
void GPUSpikingModel::allocSynapseImap( int count )
{
	SynapseIndexMap synapseIndexMap;

	checkCudaErrors( cudaMalloc( ( void ** ) &synapseIndexMap.outgoingSynapseBegin, count * sizeof( BGSIZE ) ) );
	checkCudaErrors( cudaMalloc( ( void ** ) &synapseIndexMap.outgoingSynapseCount, count * sizeof( BGSIZE ) ) );
	checkCudaErrors( cudaMemset(synapseIndexMap.outgoingSynapseBegin, 0, count * sizeof( BGSIZE ) ) );
	checkCudaErrors( cudaMemset(synapseIndexMap.outgoingSynapseCount, 0, count * sizeof( BGSIZE ) ) );

	checkCudaErrors( cudaMalloc( ( void ** ) &synapseIndexMap.incomingSynapseBegin, count * sizeof( BGSIZE ) ) );
	checkCudaErrors( cudaMalloc( ( void ** ) &synapseIndexMap.incomingSynapseCount, count * sizeof( BGSIZE ) ) );
	checkCudaErrors( cudaMemset(synapseIndexMap.incomingSynapseBegin, 0, count * sizeof( BGSIZE ) ) );
	checkCudaErrors( cudaMemset(synapseIndexMap.incomingSynapseCount, 0, count * sizeof( BGSIZE ) ) );

	checkCudaErrors( cudaMalloc( ( void ** ) &synapseIndexMapDevice, sizeof( SynapseIndexMap ) ) );
	checkCudaErrors( cudaMemcpy( synapseIndexMapDevice, &synapseIndexMap, sizeof( SynapseIndexMap ), cudaMemcpyHostToDevice ) );
}

/*
 *  Deallocate device memory for synapse inverse map.
 */
void GPUSpikingModel::deleteSynapseImap(  )
{
	SynapseIndexMap synapseIndexMap;

	checkCudaErrors( cudaMemcpy ( &synapseIndexMap, synapseIndexMapDevice, sizeof( SynapseIndexMap ), cudaMemcpyDeviceToHost ) );

	checkCudaErrors( cudaFree( synapseIndexMap.outgoingSynapseBegin ) );
	checkCudaErrors( cudaFree( synapseIndexMap.outgoingSynapseCount ) );
	checkCudaErrors( cudaFree( synapseIndexMap.outgoingSynapseIndexMap ) );

	checkCudaErrors( cudaFree( synapseIndexMap.incomingSynapseBegin ) );
	checkCudaErrors( cudaFree( synapseIndexMap.incomingSynapseCount ) );
	checkCudaErrors( cudaFree( synapseIndexMap.incomingSynapseIndexMap ) );

	checkCudaErrors( cudaFree( synapseIndexMapDevice ) );
}

/* 
 *  Copy SynapseIndexMap in host memory to SynapseIndexMap in device memory.
 *
 *  @param  synapseIndexMapHost		Reference to the SynapseIndexMap in host memory.
 *  @param  neuron_count		The number of neurons.
 */
void GPUSpikingModel::copySynapseIndexMapHostToDevice(SynapseIndexMap &synapseIndexMapHost, int neuron_count)
{
        int total_synapse_counts = dynamic_cast<AllSynapses*>(m_synapses)->total_synapse_counts;

	if (total_synapse_counts == 0)
		return;

	SynapseIndexMap synapseIndexMap;

	checkCudaErrors( cudaMemcpy ( &synapseIndexMap, synapseIndexMapDevice, sizeof( SynapseIndexMap ), cudaMemcpyDeviceToHost ) );

        // forward map
	checkCudaErrors( cudaMemcpy ( synapseIndexMap.outgoingSynapseBegin, synapseIndexMapHost.outgoingSynapseBegin, neuron_count * sizeof( BGSIZE ), cudaMemcpyHostToDevice ) );
	checkCudaErrors( cudaMemcpy ( synapseIndexMap.outgoingSynapseCount, synapseIndexMapHost.outgoingSynapseCount, neuron_count * sizeof( BGSIZE ), cudaMemcpyHostToDevice ) );
	// the number of synapses may change, so we reallocate the memory
	if (synapseIndexMap.outgoingSynapseIndexMap != NULL) {
		checkCudaErrors( cudaFree( synapseIndexMap.outgoingSynapseIndexMap ) );
	}
	checkCudaErrors( cudaMalloc( ( void ** ) &synapseIndexMap.outgoingSynapseIndexMap, total_synapse_counts * sizeof( BGSIZE ) ) );
	checkCudaErrors( cudaMemcpy ( synapseIndexMap.outgoingSynapseIndexMap, synapseIndexMapHost.outgoingSynapseIndexMap, total_synapse_counts * sizeof( BGSIZE ), cudaMemcpyHostToDevice ) );

        // active synapse map
	checkCudaErrors( cudaMemcpy ( synapseIndexMap.incomingSynapseBegin, synapseIndexMapHost.incomingSynapseBegin, neuron_count * sizeof( BGSIZE ), cudaMemcpyHostToDevice ) );
	checkCudaErrors( cudaMemcpy ( synapseIndexMap.incomingSynapseCount, synapseIndexMapHost.incomingSynapseCount, neuron_count * sizeof( BGSIZE ), cudaMemcpyHostToDevice ) );
	// the number of synapses may change, so we reallocate the memory
	if (synapseIndexMap.incomingSynapseIndexMap != NULL) {
		checkCudaErrors( cudaFree( synapseIndexMap.incomingSynapseIndexMap ) );
	}
	checkCudaErrors( cudaMalloc( ( void ** ) &synapseIndexMap.incomingSynapseIndexMap, total_synapse_counts * sizeof( BGSIZE ) ) );
	checkCudaErrors( cudaMemcpy ( synapseIndexMap.incomingSynapseIndexMap, synapseIndexMapHost.incomingSynapseIndexMap, total_synapse_counts * sizeof( BGSIZE ), cudaMemcpyHostToDevice ) );

	checkCudaErrors( cudaMemcpy ( synapseIndexMapDevice, &synapseIndexMap, sizeof( SynapseIndexMap ), cudaMemcpyHostToDevice ) );
}

/* ------------------*\
|* # Global Functions
\* ------------------*/

/* 
 * @param[in] totalNeurons       Number of neurons.
 * @param[in] allNeuronsDevice   Pointer to Neuron structures in device memory.
 * @param[in] synapseIndexMap    forward map.
 * @param[in] allSynapsesDevice  Pointer to Synapse structures in device memory.
 */
__global__ void calcSummationMapDevice( int totalNeurons, AllSpikingNeuronsDeviceProperties* allNeuronsDevice, SynapseIndexMap* synapseIndexMapDevice, AllSpikingSynapsesDeviceProperties* allSynapsesDevice ) {
        int idx = blockIdx.x * blockDim.x + threadIdx.x;
        if ( idx >= totalNeurons )
                return;

        BGSIZE iCount = synapseIndexMapDevice->incomingSynapseCount[idx];
        if (iCount != 0) {
                int beginIndex = synapseIndexMapDevice->incomingSynapseBegin[idx];
                BGSIZE* activeMap_begin = &( synapseIndexMapDevice->incomingSynapseIndexMap[beginIndex] );
                BGFLOAT sum = 0.0;
                BGSIZE syn_i = activeMap_begin[0];
                for ( BGSIZE i = 0; i < iCount; i++ ) {
                        syn_i = activeMap_begin[i];
                        sum += allSynapsesDevice->psr[syn_i];
                }
                allNeuronsDevice->summation_map[idx] = sum;
        }
}

