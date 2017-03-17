#include "SimulationInfo.h"
#include "ParseParamError.h"

/*
 *  Checks the number of required parameters.
 *
 * @return true if all required parameters were successfully read, false otherwise.
 */
bool SimulationInfo::checkNumParameters()
{
    return (nParams >= 5);
}

/*
 *  Attempts to read parameters from a XML file.
 *
 *  @param  simDoc  the TiXmlDocument to read from.
 *  @return true if successful, false otherwise.
 */
bool SimulationInfo::readParameters(TiXmlDocument* simDoc)
{
    TiXmlElement* parms = NULL;

    if ((parms = simDoc->FirstChildElement("SimInfoParams")) == NULL) {
        cerr << "Could not find <SimInfoParms> in simulation parameter file " << endl;
        return false;
    }

    try {
         parms->Accept(this);
    } catch (ParseParamError &error) {
        error.print(cerr);
        cerr << endl;
        return false;
    }

    // check to see if all required parameters were successfully read
    if (checkNumParameters() != true) {
        cerr << "Some parameters are missing in <SimInfoParams> in simulation parameter file " << endl;
        return false;
    }

    return true;
}

/*
 *  Handles loading of parameters using tinyxml from the parameter file.
 *
 *  @param  element TiXmlElement to examine.
 *  @param  firstAttribute  ***NOT USED***.
 *  @return true if method finishes without errors.
 */
bool SimulationInfo::VisitEnter(const TiXmlElement& element, const TiXmlAttribute* firstAttribute)
//TODO: firstAttribute does not seem to be used! Delete?
{
    if (element.ValueStr().compare("SimInfoParams") == 0) {
        return true;
    } 

    if (element.ValueStr().compare("PoolSize") == 0) {
        if (element.QueryIntAttribute("x", &width) != TIXML_SUCCESS) {
            throw ParseParamError("PoolSize x", "PoolSize missing x value in XML.");
        }
        if (element.QueryIntAttribute("y", &height) != TIXML_SUCCESS) {
            throw ParseParamError("PoolSize y", "PoolSize missing y value in XML.");
        }
        if (width < 0 || height < 0) {
            throw ParseParamError("PoolSize", "Invalid negative PoolSize value.");
        }
        //z dimmension is for future expansion and not currently supported
        totalNeurons = width * height;
        nParams++;
        return true;
    }

    if (element.ValueStr().compare("SimParams") == 0) {
        if (element.QueryFLOATAttribute("Tsim", &epochDuration) != TIXML_SUCCESS) {
            throw ParseParamError("SimParams Tsim", "SimParams missing Tsim value in XML.");
        }
        if (element.QueryIntAttribute("numSims", &maxSteps) != TIXML_SUCCESS) {
            throw ParseParamError("SimParams numSims", "SimParams missing numSims value in XML.");
        }
        if (epochDuration < 0 || maxSteps < 0) {
            throw ParseParamError("SimParams", "Invalid negative SimParams value.");
        }
        nParams++;
        return true;
    }

    if (element.ValueStr().compare("SimConfig") == 0) {
        if (element.QueryIntAttribute("maxFiringRate", &maxFiringRate) != TIXML_SUCCESS) {
            throw ParseParamError("SimConfig maxFiringRate", "SimConfig missing maxFiringRate value in XML.");
        }
        if (element.QueryIntAttribute("maxSynapsesPerNeuron", &maxSynapsesPerNeuron) != TIXML_SUCCESS) {
            throw ParseParamError("SimConfig maxSynapsesPerNeuron", "SimConfig missing maxSynapsesPerNeuron value in XML.");
        }
        if (maxFiringRate < 0 || maxSynapsesPerNeuron < 0) {
            throw ParseParamError("SimConfig", "Invalid negative SimConfig value.");
        }
        nParams++;
        return true;
    }

    if (element.ValueStr().compare("Seed") == 0) {
        if (element.QueryValueAttribute("value", &seed) != TIXML_SUCCESS) {
            throw ParseParamError("Seed value", "Seed missing value in XML.");
        }
        nParams++;
        return true;
    }

    if (element.ValueStr().compare("OutputParams") == 0) {
        // file name specified in commond line is higher priority
        if (stateOutputFileName.empty()) {
            if (element.QueryValueAttribute("stateOutputFileName", &stateOutputFileName) != TIXML_SUCCESS) {
                throw ParseParamError("OutputParams stateOutputFileName", "OutputParams missing stateOutputFileName value in XML.");
            }
        }
        nParams++;
        return true;
    }

    return false;
}

/*
 *  Prints out loaded parameters to ostream.
 *
 *  @param  output  ostream to send output to.
 */
void SimulationInfo::printParameters(ostream &output) const
{
    cout << "poolsize x:" << width << " y:" << height
         //z dimmension is for future expansion and not currently supported
         //<< " z:" <<
         << endl;
    cout << "Simulation Parameters:\n";
    cout << "\tTime between growth updates (in seconds): " << epochDuration << endl;
    cout << "\tNumber of simulations to run: " << maxSteps << endl;
}

/*-----------------------------------------------------------------------------

-----------------------------------------------------------------------------*/

namespace cereal {

	template<class Archive>
	void save(Archive& archive, const SimulationInfo& simInfo) {
		archive(simInfo.width, simInfo.height, simInfo.totalNeurons, simInfo.currentStep,
			simInfo.maxSteps, simInfo.epochDuration, simInfo.maxFiringRate,
			simInfo.maxSynapsesPerNeuron, simInfo.maxSynapsesPerNeuron, simInfo.deltaT,
			simInfo.rgNeuronTypeMap, simInfo.rgEndogenouslyActiveNeuronMap,
			simInfo.maxFiringRate, simInfo.pSummationMap, simInfo.seed, simInfo.stateOutputFileName,
			simInfo.stateInputFileName, simInfo.memOutputFileName, simInfo.memInputFileName,
			simInfo.stimulusInputFileName, simInfo.model, simInfo.simRecorder, simInfo.pInput,
			simInfo.nParams);
	}

	template<class Archive>
	void load(Archive& archive, SimulationInfo& simInfo) {
		archive(simInfo.width, simInfo.height, simInfo.totalNeurons, simInfo.currentStep,
			simInfo.maxSteps, simInfo.epochDuration, simInfo.maxFiringRate,
			simInfo.maxSynapsesPerNeuron, simInfo.maxSynapsesPerNeuron, simInfo.deltaT,
			simInfo.rgNeuronTypeMap, simInfo.rgEndogenouslyActiveNeuronMap,
			simInfo.maxFiringRate, simInfo.pSummationMap, simInfo.seed, simInfo.stateOutputFileName,
			simInfo.stateInputFileName, simInfo.memOutputFileName, simInfo.memInputFileName,
			simInfo.stimulusInputFileName, simInfo.model, simInfo.simRecorder, simInfo.pInput,
			simInfo.nParams);
	}

}
