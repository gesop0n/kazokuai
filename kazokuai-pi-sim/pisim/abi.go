package main

const (
	gpioGetChipInfo       = 0x8044b401
	gpioGetLineInfoUnwat  = 0xc004b40c
	gpioV2GetLineInfo     = 0xc100b405
	gpioV2GetLineInfoWat  = 0xc100b406
	gpioV2GetLine         = 0xc250b407
	gpioV2LineSetConfig   = 0xc110b40d
	gpioV2LineGetValues   = 0xc010b40e
	gpioV2LineSetValues   = 0xc010b40f
	gpioV1GetLineInfo     = 0xc048b402
	gpioV1GetLineHandle   = 0xc16cb403
	gpioV1GetLineEvent    = 0xc030b404
	gpioV1HandleGetValues = 0xc040b408
	gpioV1HandleSetValues = 0xc040b409
	gpioV1HandleSetConfig = 0xc054b40a
	gpioV1GetLineInfoWat  = 0xc048b40b
)

var gpioIoctls = []uint32{
	gpioGetChipInfo, gpioGetLineInfoUnwat,
	gpioV2GetLineInfo, gpioV2GetLineInfoWat, gpioV2GetLine,
	gpioV2LineSetConfig, gpioV2LineGetValues, gpioV2LineSetValues,
	gpioV1GetLineInfo, gpioV1GetLineHandle, gpioV1GetLineEvent,
	gpioV1HandleGetValues, gpioV1HandleSetValues, gpioV1HandleSetConfig, gpioV1GetLineInfoWat,
}

const (
	sizeChipInfo     = 68
	sizeV2LineInfo   = 256
	sizeV2LineReq    = 592
	sizeV2LineConfig = 272
	sizeV2Values     = 16
	sizeV2Event      = 48
	sizeV1LineInfo   = 72
	sizeV1HandleReq  = 364
	sizeV1HandleConf = 84
	sizeV1HandleData = 64
	sizeV1EventReq   = 48
	sizeV1EventData  = 16
)

const (
	v2FlagUsed        = 1 << 0
	v2FlagActiveLow   = 1 << 1
	v2FlagInput       = 1 << 2
	v2FlagOutput      = 1 << 3
	v2FlagEdgeRising  = 1 << 4
	v2FlagEdgeFalling = 1 << 5
	v2FlagOpenDrain   = 1 << 6
	v2FlagOpenSource  = 1 << 7
	v2FlagPullUp      = 1 << 8
	v2FlagPullDown    = 1 << 9
	v2FlagBiasDisable = 1 << 10
	v2FlagClockRT     = 1 << 11
	v2FlagClockHTE    = 1 << 12
)

const (
	v2AttrFlags        = 1
	v2AttrOutputValues = 2
	v2AttrDebounce     = 3
)

const (
	v2EventRising  = 1
	v2EventFalling = 2
)

const (
	v1ReqInput       = 1 << 0
	v1ReqOutput      = 1 << 1
	v1ReqActiveLow   = 1 << 2
	v1ReqOpenDrain   = 1 << 3
	v1ReqOpenSource  = 1 << 4
	v1ReqPullUp      = 1 << 5
	v1ReqPullDown    = 1 << 6
	v1ReqBiasDisable = 1 << 7
)

const (
	v1InfoKernel      = 1 << 0
	v1InfoIsOut       = 1 << 1
	v1InfoActiveLow   = 1 << 2
	v1InfoOpenDrain   = 1 << 3
	v1InfoOpenSource  = 1 << 4
	v1InfoPullUp      = 1 << 5
	v1InfoPullDown    = 1 << 6
	v1InfoBiasDisable = 1 << 7
)

const (
	v1EventRequestRising  = 1 << 0
	v1EventRequestFalling = 1 << 1
)

const maxLinesPerRequest = 64

const (
	sysIoctl           = 16
	sysClockGettime    = 228
	sysSetns           = 308
	sysProcessVMReadv  = 310
	sysProcessVMWritev = 311
	sysSeccomp         = 317
)

const (
	seccompSetModeFilter   = 1
	seccompFlagNewListener = 1 << 3
	seccompRetAllow        = 0x7fff0000
	seccompRetUserNotif    = 0x7fc00000
	seccompNotifRecv       = 0xc0502100
	seccompNotifSend       = 0xc0182101
	seccompNotifIDValid    = 0x40082102
	seccompNotifAddFD      = 0x40182103
	seccompNotifFlagCont   = 1
	seccompDataNrOffset    = 0
	seccompDataArchOffset  = 4
	seccompDataArgsOffset  = 16
	sizeSeccompNotif       = 80
	sizeSeccompNotifResp   = 24
	sizeSeccompNotifAddFD  = 24
	auditArchX86_64        = 0xc000003e
)

const (
	oCloexec       = 0x80000
	clockRealtime  = 0
	clockMonotonic = 1
)

const (
	errnoEPERM  = 1
	errnoENOENT = 2
	errnoEBADF  = 9
	errnoENOMEM = 12
	errnoEFAULT = 14
	errnoEBUSY  = 16
	errnoEINVAL = 22
	errnoENOTTY = 25
)
