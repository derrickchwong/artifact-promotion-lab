// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	_ "path"
	"strings"

	"rsc.io/quote"
)

func main() {
	handler := GetHTTPHandlers()
	/* #nosec */
	http.ListenAndServe(fmt.Sprintf("0.0.0.0:8080"), &handler)
}

// GetHTTPHandlers sets up and runs the main http server
func GetHTTPHandlers() (handlers http.ServeMux) {
	handler := new(http.ServeMux)
	handler.HandleFunc("/", SayHelloHandler)
	handler.HandleFunc("/_health", HealthCheckHandler)

	return *handler
}

// SayHelloHandler handles a response
func SayHelloHandler(w http.ResponseWriter, r *http.Request) {
	var output strings.Builder

	currentEnvironment := os.Getenv("ENVIRONMENT")
	w.Header().Set("Content-Type", "text/html")

	output.WriteString(fmt.Sprintf("<html><head><title>HI ALL hello there! - %s</title></head><body>", currentEnvironment))

	output.WriteString("<h1>Hi AppTeam!</h1>")                                     // ##_CHANGE ME_##

	output.WriteString(fmt.Sprintf("<h2>Random Quote: %s</h2>", quote.Glass())) // Opt()
	output.WriteString(fmt.Sprintf("<h2>Current Environment: %s</h2>", currentEnvironment))
	output.WriteString("</body><html>")

	// write output to stream
	fmt.Fprintf(w, output.String())
}

// HealthCheckHandler responds with a mocked "ok" (real prod app should do some work here)
func HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Header().Set("Content-Type", "application/json")

	_, err := io.WriteString(w, `{"alive": true}`)
	if err != nil {
		// fmt.Errorf("Unable to write to reponse with error: %w", err)
		log.Fatal(err)
	}
}
