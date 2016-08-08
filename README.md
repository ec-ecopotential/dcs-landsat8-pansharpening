## Developer Cloud Sandbox for Landsat 8 pan-sharpening with GDAL and the Orfeo ToolBox (OTB) 

Pan-sharpening is a process of merging high-resolution panchromatic and lower resolution multispectral imagery to create a single high-resolution color image. 

This processing service uses Landsat panchromatic band at 15 meter resolution to provide greater detail in the Landsat red, green and blue bands (4-3-2). 

This processing services uses GDAL and the Orfeo Toolbox.

The Geospatial Data Abstraction Library (GDAL) is an open source library for reading and writing raster and vector geospatial data formats.

Orfeo Toolbox (OTB) is an open source library for remote sensing image processing funded by the CNES (french space agency).

## Quick link
 
* [Getting Started](#getting-started)
* [Installation](#installation)
* [Submitting the workflow](#submit)
* [Community and Documentation](#community)
* [Authors](#authors)
* [Questions, bugs, and suggestions](#questions)
* [License](#license)
* [Funding](#funding)

### <a name="getting-started"></a>Getting Started 

To run this application you will need a Developer Cloud Sandbox that can be requested at support (at) terradue.com

A Developer Cloud Sandbox provides Earth Sciences data access services, and helper tools for a user to implement, test and validate a scalable data processing application. It offers a dedicated virtual machine and a Cloud Computing environment.
The virtual machine runs in two different lifecycle modes: Sandbox mode and Cluster mode. 
Used in Sandbox mode (single virtual machine), it supports cluster simulation and user assistance functions in building the distributed application.
Used in Cluster mode (a set of master and slave nodes), it supports the deployment and execution of the application with the power of distributed computing for data processing over large datasets (leveraging the Hadoop Streaming MapReduce technology). 

### <a name="installation"></a>Installation

#### Pre-requisites

**Installing OTB and other dependencies**

This services requires OTB, GDAL and XML Starlet

To install these packages, run the simple steps below on the Developer Cloud Sandbox shell:

```bash
sudo yum install -y OTB
sudo yum install -y gdal-t2
sudo yum install -y xmlstarlet
```

##### Using the releases

Log on the Developer Cloud Sandbox.

Download the rpm package from https://github.com/ec-ecopotential/dcs-landsat8-pansharpening/releases.

Install the downloaded package by running these commands in a shell:

```bash
sudo yum -y install dcs-landsat8-pansharpening-<version>.x86_64.rpm
```

> At this stage there are no releases yet

#### Using the development version

Install the pre-requisites as instructed above.

Log on the Developer Cloud Sandbox and run these commands in a shell:

```bash
git clone git@github.com:ec-ecopotential/dcs-landsat8-pansharpening.git
cd dcs-landsat8-pansharpening
mvn install
```

### <a name="submit"></a>Submitting the workflow

To submit the application with its default parameters, run the command below in the Developer Cloud Sandbox shell:

```bash
ciop-run
```
Or invoke the Web Processing Service via the Sandbox dashboard providing the catalogue references to the Landat 8 data to process.

### <a name="community"></a>Community and Documentation

To learn more and find information go to 

* [Developer Cloud Sandbox](http://docs.terradue.com/developer)  
* [Orfeo Toolbox](https://www.orfeo-toolbox.org/)
* [GDAL](http://www.gdal.org/)
* [Landsat 8](http://landsat.usgs.gov/landsat8.php) 

### <a name="authors"></a>Authors (alphabetically)

* Brito Fabrice
* Rossi Cesare

### <a name="questions"></a>Questions, bugs, and suggestions

Please file any bugs or questions as [issues](https://github.com/ec-ecopotential/dcs-landsat8-pansharpening/issues/new) or send in a pull request if you corrected any.

### <a name="license"></a>License

Copyright 2016 Terradue Srl

Licensed under the Apache License, Version 2.0: http://www.apache.org/licenses/LICENSE-2.0

### <a name="funding"></a>Funding

The ECOPOTENTIAL project has received funding from the European Union's Horizon 2020 research and innovation programme under grant agreement No 641762
