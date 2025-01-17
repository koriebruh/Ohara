package helper

import "log"

func IfErrFatal(err error, msg string) {
	if err != nil {
		log.Fatalf("Error in %s: %v", msg, err)
	}
}
