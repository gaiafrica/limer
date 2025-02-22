
.get_exch_ac <- function(exch_ac, exch_Al, exch_H) {
	if (is.null(exch_ac)) {
		if (is.null(exch_Al)) {
		  stop("Either exchangeable acidity or exchangeable Al should be provided")
		} else {
			if (!is.null(exch_H)) {
				exch_Al + exch_H  
			} else {
				exch_Al
			}
		}
	} else {
		exch_ac
	}
}

.get_ECEC <- function(exch_ac=NULL, exch_bases=NULL, exch_Ca=NULL, exch_Mg=NULL, exch_K=NULL, exch_Na=NULL) {
    if (!is.null(exch_bases)){
		exch_ac + exch_bases
    } else {
		if (is.null(exch_Ca) || is.null(exch_Mg) || is.null(exch_K) || is.null(exch_Na)) {
			stop("to compute ECEC, exchangeable bases by element (Ca, Mg, K, Na) should be provided when exch_bases is NULL")
		}
		m <- cbind(exch_Ca, exch_Mg, exch_K, exch_Na)
		rowSums(m) + exch_ac  
    }
}



.check_method <- function(method) {

	av.meth <- c("litas", "kamprath", "cochrane", "numass", "brazilv", "goncalves")
	## for backwards compatibility (to be removed?)
	av.meth <- c(av.meth, "my", "bv", "gt", "te")
	## note that this uses partial matching such that "ka" is valid for "kamprath"
	## it gives an error if (length(av.meth) > 1) | (!meth %in% av.meth)
	meth <- match.arg(tolower(method), av.meth) 
	meth <- substr(meth, 1, 2)
  
## for backwards compatibility
	if (meth == "my") {
		meth <- "li"
	} else if (meth == "bv") {
		meth <- "br"
	} else if (meth %in% c("te", "gt")) {
		meth <- "go"
	}
	meth

}


.lr <- function(method, unit = "meq/100g", check_Ca = TRUE, SD = 20,
                exch_ac = NULL, exch_bases = NULL, ECEC = NULL, SBD = NULL, 
                exch_Al = NULL, exch_H = NULL, 
                exch_Ca = NULL, exch_Mg = NULL, exch_K = NULL, exch_Na = NULL,
                CEC_7 = NULL, pot_ac = NULL, pH = NULL, OM = NULL, clay = NULL,
                TAS = NULL, target_Ve = NULL, X = NULL, crop_type = NULL) {
  
  
	meth <- .check_method(method[1])
	unit <- match.arg(unit[1], c("meq/100g", "kg/ha", "t/ha"))
  
	if ((unit %in% c("kg/ha", "t/ha")) || check_Ca){
		if (is.null(SBD)) {
			stop("Soil bulk density (SBD) is needed to estimate lime requirement in kg/ha or t/ha, and for Ca deficiencies check")
		}
		if (check_Ca && is.null(exch_Ca)){
			stop("exch_Ca is needed to test for Ca deficiencies")
		}
	}

	exch_ac <- .get_exch_ac(exch_ac, exch_Al, exch_H)
  
	if (is.null(ECEC) && (meth != "ka")) {
		ECEC <- .get_ECEC(exch_ac, exch_bases, exch_Ca, exch_Mg, exch_K, exch_Na)
    }
	# specific
	if (meth %in% c("li", "co", "nu")){
		if (is.null(TAS)) stop("TAS is needed for this method")
	}
    
	# compute lime requirement by method
	if (meth == "li") {
		# message("using LiTAS method")
		lime <- .lr_litas(exch_ac = exch_ac, ECEC = ECEC, TAS = TAS)
	} else if (meth == "ka") {
		# message("using Kamprath (1970) method")
		lime <- .lr_ka(exch_ac = exch_ac)
	} else if (meth == "co") {
		# message("using Cochrane et al. (1980) method")
		lime <- .lr_co(exch_ac = exch_ac, ECEC = ECEC, TAS = TAS)
	} else if (meth == "nu") {
		# message("using NuMaSS method")
		lime <- .lr_nu(exch_ac = exch_ac, ECEC = ECEC, TAS = TAS, clay = clay)
	} else if (meth %in% c("br", "go")) {
		if(is.null(exch_bases)) {
		  exch_bases <- ECEC - exch_ac  
		}
		if(is.null(CEC_7) && is.null(pot_ac)) {
		  stop("CEC_7 or pot_ac is needed for this method")
		}
		if (meth == "br") {
		# message("using Brazil V method")
			if (is.null(CEC_7)) { # & !is.null(pot_ac)){
				CEC_7 <- pot_ac + exch_bases
			}
			if (is.null(target_Ve) && is.null(crop_type)){
				stop("target base saturation (target_Ve) or crop type are needed for this method")
			}  
			lime <- .lr_bv(exch_bases = exch_bases, CEC_7 = CEC_7, 
					   target_Ve = target_Ve, crop_type = crop_type)
		} else if (meth == "go") {
		# message("using Goncalvez Teixeira method")
		## was: if(!is.null(pot_ac) & is.null(CEC_7)){
			if(is.null(pot_ac)) { # & is.null(CEC_7)){
				pot_ac <- CEC_7 - exch_bases
			}
	  
			if(is.null(pH) || is.null(OM)) { # |is.null(pot_ac)){
				stop("pH, OM, and pot_ac or CEC_7 are needed for the Goncalvez method")
			}
			lime <- .lr_gt(pH = pH, OM = OM, pot_ac = pot_ac, X = X, 
					   exch_Ca = exch_Ca, exch_Mg = exch_Mg)
		}
	}
	# Final steps
  	# remove negative values 
	lime[lime < 0] <- 0
	  
	# unit transformation
	if (unit %in% c("kg/ha", "t/ha")) {
		lime <- convert(lime, SBD = SBD, SD = SD, to_t_ha = TRUE)
		if (unit == "kg/ha") lime <- lime * 1000
	}
  
	if (check_Ca) {
		lime <- .ca_def(lime = lime, exch_Ca = exch_Ca, ECEC = ECEC, unit = unit, SBD = SBD, SD = SD)
	}
	
	lime
}

# end limer 

# individual formulas

# Kamprath (1970) 
.lr_ka <- function(exch_ac, lf = 1.5){
	exch_ac * lf
}

# Cochrane, et al. (1980).
.lr_co <- function(exch_ac, ECEC, TAS){
	ias <- 100 * exch_ac/ECEC
	d_ac <- exch_ac - (TAS/100 * ECEC)
	llf <- TAS > ias/3
	ifelse(llf, 1.5 * d_ac, 2 * d_ac)
}

# NUMASS (Osmond et al., 2002)
# lf is converted from original formula to get lime recommendation in meq/100g assuming that the original formula considered a soil depth of 15 cm and a soil bulk density of 1g/cm3

.lr_nu <- function(exch_ac, ECEC, TAS, clay = NULL){
  # normal lf (high clay activity)
  lime1 <- 26/15 * exch_ac - (TAS/100 * ECEC)
  #if clay data is available, modify lf when clay activity is very low
  if(!is.null(clay)){
    lclay <- ECEC/clay < 4.5 & !is.na(clay) & !is.na(ECEC)
    lime1[lclay] <- lime1[lclay] * 25/13    
  }
  # second part of the formula, which has to be positive
  lime2 <- 10 * ((19 - TAS)/100 * ECEC)
  lime2[lime2 < 0] <- 0
  # add first and second part
  lime1 + lime2
}


# Aramburu Merlos et al. xxx
.lr_litas <- function(exch_ac, ECEC, TAS, a = 0.6, b = 0.2){
  tas <- TAS/100
  lf <- 1/(a + tas * (b-a))
  pmax(0, lf * (exch_ac - tas * ECEC))
}


# Brazil V method (van Raij 1996) 
.lr_bv <- function(exch_bases, CEC_7, target_Ve = NULL, crop_type){
  if(is.null(target_Ve)){
    Ve <- data.frame(ct = c("pasture", "cereal", "legume", "vegetable", "fruit"), 
                     tVe = c(40, 50, 50, 70, 70))
    i <- match(crop_type, Ve$ct)
    target_Ve <- Ve$tVe[i]
    if(any(is.na(target_Ve))){
      stop("unrecognized crop type. Crop type can be pasture, cereal, legume, vegetable, or fruit.")
    }
  }
  Ve <- target_Ve/100
  CEC_7 * Ve - exch_bases
}


# Goncalvez Teixeira et al., (2020)
.lr_gt <- function(pH, OM, pot_ac, X = NULL, exch_Ca = NULL, exch_Mg = NULL){
  om5 <- 0.0699 * (((5.8 - pH)* OM)^0.9225)
  ac5 <- 0.3750 * (((5.8 - pH)* pot_ac)^0.9127)
  om6 <- 0.1059 * (((6.0 - pH)* OM)^0.8729)
  ac6 <- 0.4558 * (((6.0 - pH)* pot_ac)^0.9162)
  m <- cbind(om5, om6, ac5, ac6)
  
  if(!is.null(X)){
    if(length(X) > 1) stop("X should be only one value")  
    if(is.null(exch_Ca) | is.null(exch_Mg)){
      stop("exchangeable Ca and Mg are required to adjust for crop Ca and Mg requirement")
    }
    if(length(exch_Ca) != length(exch_Mg)){
      warning("exchangeable Ca and Mg have different lengths")
    }
    # lime required to reach the minimum Ca and Mg level 
    lr_CaMg <- rep(X, length(exch_Ca)) - exch_Ca - exch_Mg
    # omit lime requirements that do not meet the min Ca-Mg level
    lX <- apply(m, 2, FUN = function(x) x < lr_CaMg)
    m[lX] <- NA
    # if all lr are lower than the min level for Ca and Mg
    all.na <- apply(m, 1, function(x)all(is.na(x)))
    # assign the min lr for Ca and Mg in the first column 
    m[all.na, 1] <- ifelse(length(lr_CaMg) == 1, lr_CaMg, lr_CaMg[all.na])
  }
  # select the min lr for each observation
  lime <- apply(m, 1, min, na.rm = T)
  # the lr cannot exceed the potential acidity of the soil
  lime[lime > pot_ac] <- pot_ac
  lime
}

# check Ca deficiencies: 150kg/ha when Ca saturation < 25% (PS Book)
.ca_def <- function(lime, exch_Ca, ECEC, unit, SBD, SD){
  def <- exch_Ca/ECEC < 0.25 & !is.na(exch_Ca) & !is.na(ECEC)
  if(unit == "kg/ha"){
    dose <- 150
  } else if(unit == "t/ha"){
    dose <- 0.15
  } else {
    dose <- convert(0.15, SBD, SD, to_t_ha = FALSE)[def]
    dose[is.na(dose)] <- 0 # if dose is.na, keep current lime rate (including NAs)
  }
  lime[def] <- pmax(lime[def], dose)
  lime
}

