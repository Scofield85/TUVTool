library(dplyr)
library(lubridate)
require(sp)
# readingRawFile <- function(filename){
# 	# filename <- "/Users/WenzhaoXu/Developer/Triaxus/previous/LOPCData/NS_2013_HU6_HU7_2.dat"
# 	lines <- strsplit(readLines(filename),"\\s+|,")
# 	date <- lines[[2]][5,6,8]
# 	date <- as.Date(paste(date,collapse = "_"),format = "%B_%d_%Y")
# 	Seabird_idx <- sapply(lines,function(i) "S" %in% i & length(i) == 11)
# 	Fluoroprobe_idx <- sapply(lines,function(i) "F" %in% i)
# 	Phytoflash_idx <- sapply(lines,function(i) "C" %in% i)
# 	geo_idx <- sapply(lines,function(i) "$GPGGA" %in% i & length(i)==15)

# 	LOPC_L1_idx <- sapply(lines,function(i) "L1" %in% i)
# 	LOPC_L2_idx <- sapply(lines,function(i) "L2" %in% i)
# 	LOPC_L3_idx <- sapply(lines,function(i) "L3" %in% i)
# 	LOPC_L4_idx <- sapply(lines,function(i) "L4" %in% i)
# 	LOPC_L5_idx <- sapply(lines,function(i) "L5" %in% i)

# 	SeabirdData <- apply((do.call(rbind,lines[Seabird_idx])[,-1]), 2,as.numeric)
# 	Fluoroprobe <- apply((do.call(rbind,lines[Fluoroprobe_idx])[,-1]), 2,as.numeric)
# 	Phytoflash <- (do.call(rbind,lines[Phytoflash_idx])[,-1])
# 	# Phytoflash[,3:7] <- as.numeric(Phytoflash[,3:7])
# 	geoData <- apply(do.call(rbind,lines[geo_idx])[,-1][,c(1,2,4)],2,as.numeric)
# 	geoData[,3] <- -geoData[,3]

# 	LOPC_L1  <- apply((do.call(rbind,lines[LOPC_L1_idx])[,-1]), 2,as.numeric)
# 	LOPC_L2  <- apply((do.call(rbind,lines[LOPC_L2_idx])[,-1]), 2,as.numeric)
# 	LOPC_L3  <- apply((do.call(rbind,lines[LOPC_L3_idx])[,-1]), 2,as.numeric)
# 	LOPC_L4  <- apply((do.call(rbind,lines[LOPC_L4_idx])[,-1]), 2,as.numeric)
# 	LOPC_L5  <- apply((do.call(rbind,lines[LOPC_L5_idx])[,-1]), 2,as.numeric)
# 	LOPC <- do.call(cbind,c(LOPC_L1,LOPC_L2,LOPC_L3,LOPC_L4,LOPC_L5))
# }

lonlatTransform <- function(x){
	y <- as.numeric(substr(x,1,2))+as.numeric(substr(x,3,7))/60
	return(y)
}

distanceSpeedCalculation <- function(data){
	# data has two columns: timePassSecond, longitude and latitude
	# second 
	distance <- rep(0,nrow(data))
	speed <- rep(0,nrow(data))
	locData <- as.matrix(data[,2:3])
	distance[1:100] <- spDistsN1(locData[1:100,],locData[1,],longlat=TRUE) # km
	speed[2:100] <- sapply(2:100,function(i) (distance[i]-distance[1])/(data$timePassSecond[i]-data$timePassSecond[1]))
		
	for(i in 101:nrow(data)){
						# print(i)
            delt_Dis=spDistsN1(matrix(locData[i,],ncol=2),locData[i-99,],longlat=TRUE);
            distance[i]=delt_Dis+distance[i-99];
            speed[i] = (distance[i]-distance[i-99])/(data$timePassSecond[i]-data$timePassSecond[i-99])
    }
    return(list(distance=distance,shipSpeed=speed*1000))
}


LOPCFeature<-function(data){
  # Calculate the LOPC biomass and biodensity data
    AveFlowCnt <- data$DeltaTime/data$FlowCounts
  
    data$flowSpeed=ifelse(AveFlowCnt<=13,23.10410966*exp(-(-1.481499106*sqrt(sqrt(AveFlowCnt))+1.566460406*sqrt(AveFlowCnt)+0.196311142*sqrt(AveFlowCnt)^2-0.05*sqrt(AveFlowCnt)^3)),0.198996019*exp(-(-2.603059062*sqrt(sqrt(AveFlowCnt))+0.892897609*sqrt(AveFlowCnt)+0.006191239*sqrt(AveFlowCnt)^2-0.0013*sqrt(AveFlowCnt)^3)));
    numPoints=nrow(data)

    if("distance" %in% names(data)){
    	averageSpeed=(data$flowSpeed*0.0049*0.5+data$shipSpeed*0.0049*0.5)/2
    }else{
    	averageSpeed=data$flowSpeed*0.0049*0.5 
    }

   	LOPCname <- paste("BIN",10:128,sep="")
    
    dia=seq(150,1920,15);
    ovolm=pi/6*dia^3/(2.585^2*10^6);
    numSum=rowSums(data[,LOPCname]);
    density=numSum/(averageSpeed*1000);
    biomass=as.matrix(data[,LOPCname])%*%ovolm/(averageSpeed*1000);
  
    return(list(density=density,biomass=biomass,flowSpeed=data$flowSpeed));
}



readingRawFile <- function(filename){
	# filename <- "/Users/WenzhaoXu/Developer/Triaxus/previous/LOPCData/NS_2013_HU6_HU7_2.dat"
	# filename <- "/Users/WenzhaoXu/Developer/Triaxus/previous/LOPCData/transect_5_night_1.dat"
	print("Starting Parsing raw File")
	lines <- strsplit(readLines(filename),"\\s+|,")
	sampleDate <- lines[[2]][c(5,6,8)]
	sampleDate <- as.Date(paste(sampleDate,collapse = "_"),format = "%B_%d_%Y")
	
	data <- list()
	geo_Line <- rep(NA,3)
	Seabird_line <- rep(NA,10)
	Fluoroprobe_Line <- rep(NA,18)
	Phytoflash_Line <- rep(NA,7)
	LOPC_line <- rep(NA,138)
	i <- 1

	# dfNames <- c("UTC","latitude","longitude","scan.count","pressure","depth","temp","cond","DO.43.mg.L","DO43...sat","DO.optode","optode.T","BAT","fpb_year","fpb_month","fpb_day","fpb_hour","fpb_min","fpb_second","depth.1","temp.1","green","bluegreen","diatom","crypto","unused","unused.1","unused.2","YS","total","transmission","pf_date","pf_time","Fo","Fm","blank","Fv","Yield","BIN1","BIN2","BIN3","BIN4","BIN5","BIN6","BIN7","BIN8","BIN9","BIN10","BIN11","BIN12","BIN13","BIN14","BIN15","BIN16","BIN17","BIN18","BIN19","BIN20","BIN21","BIN22","BIN23","BIN24","BIN25","BIN26","BIN27","BIN28","BIN29","BIN30","BIN31","BIN32","BIN33","BIN34","BIN35","BIN36","BIN37","BIN38","BIN39","BIN40","BIN41","BIN42","BIN43","BIN44","BIN45","BIN46","BIN47","BIN48","BIN49","BIN50","BIN51","BIN52","BIN53","BIN54","BIN55","BIN56","BIN57","BIN58","BIN59","BIN60","BIN61","BIN62","BIN63","BIN64","BIN65","BIN66","BIN67","BIN68","BIN69","BIN70","BIN71","BIN72","BIN73","BIN74","BIN75","BIN76","BIN77","BIN78","BIN79","BIN80","BIN81","BIN82","BIN83","BIN84","BIN85","BIN86","BIN87","BIN88","BIN89","BIN90","BIN91","BIN92","BIN93","BIN94","BIN95","BIN96","BIN97","BIN98","BIN99","BIN100","BIN101","BIN102","BIN103","BIN104","BIN105","BIN106","BIN107","BIN108","BIN109","BIN110","BIN111","BIN112","BIN113","BIN114","BIN115","BIN116","BIN117","BIN118","BIN119","BIN120","BIN121","BIN122","BIN123","BIN124","BIN125","BIN126","BIN127","BIN128","Snapshot","threshold","SampleNumber","FlowCounts","DeltaTime","BufferOverrun","LaserMonitor","ElectronicCounts","CountPeriod","LaserVoltage")
	dfNames <- c("UTC","latitude","longitude","scan.count","depth","temp","cond","BAT","DO.43.mg.L","DO43...sat","fpb_year","fpb_month","fpb_day","fpb_hour","fpb_min","fpb_second","depth.1","temp.1","green","bluegreen","diatom","crypto","unused","unused.1","unused.2","YS","total","transmission","pf_date","pf_time","Fo","Fm","blank","Fv","Yield","BIN1","BIN2","BIN3","BIN4","BIN5","BIN6","BIN7","BIN8","BIN9","BIN10","BIN11","BIN12","BIN13","BIN14","BIN15","BIN16","BIN17","BIN18","BIN19","BIN20","BIN21","BIN22","BIN23","BIN24","BIN25","BIN26","BIN27","BIN28","BIN29","BIN30","BIN31","BIN32","BIN33","BIN34","BIN35","BIN36","BIN37","BIN38","BIN39","BIN40","BIN41","BIN42","BIN43","BIN44","BIN45","BIN46","BIN47","BIN48","BIN49","BIN50","BIN51","BIN52","BIN53","BIN54","BIN55","BIN56","BIN57","BIN58","BIN59","BIN60","BIN61","BIN62","BIN63","BIN64","BIN65","BIN66","BIN67","BIN68","BIN69","BIN70","BIN71","BIN72","BIN73","BIN74","BIN75","BIN76","BIN77","BIN78","BIN79","BIN80","BIN81","BIN82","BIN83","BIN84","BIN85","BIN86","BIN87","BIN88","BIN89","BIN90","BIN91","BIN92","BIN93","BIN94","BIN95","BIN96","BIN97","BIN98","BIN99","BIN100","BIN101","BIN102","BIN103","BIN104","BIN105","BIN106","BIN107","BIN108","BIN109","BIN110","BIN111","BIN112","BIN113","BIN114","BIN115","BIN116","BIN117","BIN118","BIN119","BIN120","BIN121","BIN122","BIN123","BIN124","BIN125","BIN126","BIN127","BIN128","Snapshot","threshold","SampleNumber","FlowCounts","DeltaTime","BufferOverrun","LaserMonitor","ElectronicCounts","CountPeriod","LaserVoltage")
	
		# "BBE_time","Phyto_time","timePassSecond")
	SeabirdCount = 0
	LOPCCount = 0
	PhytoflashCount = 0
	FluoroprobeCount = 0
	geoCount = 0
	newLOPC <- FALSE

	for(line in lines){
		# Seabird Data
		if("L1" %in% line){
			if(length(LOPC_line)==138){
				data[[i]] <- c(geo_Line,Seabird_line,Fluoroprobe_Line,Phytoflash_Line,LOPC_line)
				i=i+1
			}
			LOPC_line <- c(line[-1])
		}
		else if("L2" %in% line){
			LOPC_line <- c(LOPC_line,line[-1])
		}
		else if("L3" %in% line){
			LOPC_line <- c(LOPC_line,line[-1])
		}
		else if("L4" %in% line){
			LOPC_line <- c(LOPC_line,line[-1])
		}
		else if("L5" %in% line){
			LOPC_line <- c(LOPC_line,line[-1])
			LOPCCount <- LOPCCount+1
			newLOPC <- TRUE
		}
		else if("S" %in% line && length(line) == 11){  # previous file has 11
			if(newLOPC){
				Seabird_line <- line[-1]
				newLOPC <- FALSE
				SeabirdCount <- SeabirdCount+1
			}
		}
		else if("F" %in% line && length(line) == 19){
			Fluoroprobe_Line <- line[-1]
			FluoroprobeCount <- FluoroprobeCount+1
		}
		else if("C" %in% line && length(line) == 8){
			Phytoflash_Line <- line[-1]
			PhytoflashCount <- PhytoflashCount+1
		}
		else if("$GPGGA" %in% line && length(line) == 15){
			geo_Line <- line[-1][c(1,2,4)]
			geoCount <- geoCount+1
		}
	}
	if(SeabirdCount<1){
		stop("Wrong Seabird Data")
	}
	data <- as.data.frame(do.call(rbind,data))
	data <- data[-1,]
	# data[,2] <- lonlatTransform(data[,2])
	# data[,3] <- lonlatTransform(data[,3])
	data[,-c(1,32,33)] <- apply(data[,-c(1,32,33)],2,as.numeric)
	names(data) <- dfNames
	data$DDLat <- lonlatTransform(data$latitude)
	data$DDLong <- -1*lonlatTransform(data$longitude)
	
	if(geoCount>3){

		data$UTC <- strptime(paste(sampleDate,sprintf("%06s", data$UTC),sep=" "),format = "%Y-%m-%d %H%M%S",tz = "UTC")
		dataHour <- hour(data$UTC)
		validData <- !is.na(data$UTC)
		data <- data[validData,]

		dateChangeIndex <- which(sapply(2:length(dataHour),function(i) dataHour[i] == 0 & dataHour[i-1] == 23) ==TRUE)

		if(length(dateChangeIndex)==1){
			data$UTC[dateChangeIndex:nrow(data)] <- data$UTC[dateChangeIndex:nrow(data)]+24*3600
		}else if(length(dateChangeIndex)==0){
			print("same time")
		}else{
			stop("strange UTC Time")
		}
		
		# check time monotono as some UTC may by decreasing
		travelToHistory <- which(data$UTC<data$UTC[1])
		if(length(travelToHistory)>0){
			data <- data[-travelToHistory,]
		}
		
		data$timePassSecond <- rep(NA,nrow(data))
		tmp_idx <- c(1,which(diff(data$UTC)>0)+1)
		data$timePassSecond[tmp_idx] <- data$UTC[tmp_idx]-data$UTC[1]

		for(i in 2:length(tmp_idx)){
			tmpRange <- c(tmp_idx[i-1],tmp_idx[i])
			byTime <- (data$UTC[tmpRange[2]]-data$UTC[tmpRange[1]])/(diff(tmpRange))
			data$timePassSecond[(tmpRange[1]):(tmpRange[2]-1)] <- round(seq(0,by = byTime,length.out = diff(tmpRange)),1)+data$timePassSecond[tmpRange[1]]
		}
	}else{
		print("no geo data")
		data$timePassSecond <- sep(0,by=0.5,length.out = nrow(data))
	}
	
	
	
	

	# assignTime
	data$BBE_time <- paste(data$fpb_year,data$fpb_month,data$fpb_day,data$fpb_hour,data$fpb_min,data$fpb_second,sep="-")

	# data$timePassSecond <- seq(0,length.out = nrow(data),by = 0.5)
	
	if(geoCount<3){
		return(NA)
	}else{
		geoNA <- is.na(data$DDLong) | is.na(data$DDLat)
		data <- data[!geoNA,]
		tmp<- distanceSpeedCalculation(data[,c("timePassSecond","DDLong","DDLat")])
		data$shipSpeed <- tmp$shipSpeed
		data$Distance <- tmp$distance
	}
	LOPC_res <- LOPCFeature(data)
	data$Zdens <- LOPC_res$density
	data$Zug <- LOPC_res$biomass
	data$Spec.Cond <- data$cond/(1+0.02*(data$temp-25))
	data <- subset(data,!is.na(data$depth))
	print("Finish Parsing raw File")
	return(data)
	# Calculate distance, zooplankton biomass, density, longitude,latitude
}