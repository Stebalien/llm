;;; llm-gemini.el --- LLM implementation of Google Cloud Gemini AI -*- lexical-binding: t -*-

;; Copyright (c) 2023  Free Software Foundation, Inc.

;; Author: Andrew Hyatt <ahyatt@gmail.com>
;; Homepage: https://github.com/ahyatt/llm
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; This file implements the llm functionality defined in llm.el, for Google's
;; Gemini AI. The documentation is at
;; https://ai.google.dev/tutorials/rest_quickstart.

;;; Code:

(require 'cl-lib)
(require 'llm)
(require 'llm-request)
(require 'llm-vertex)
(require 'json)

(cl-defstruct llm-gemini
  "A struct representing a Gemini client.

KEY is the API key for the client.
You can get this at https://makersuite.google.com/app/apikey."
  key (embedding-model "embedding-001") (chat-model "gemini-pro"))

(defun llm-gemini--embedding-url (provider)
  "Return the URL for the EMBEDDING request for STRING from PROVIDER."
  (format "https://generativelanguage.googleapis.com/v1beta/models/%s:embedContent?key=%s"
          (llm-gemini-embedding-model provider)
          (llm-gemini-key provider)))

(defun llm-gemini--embedding-request (provider string)
  "Return the embedding request for STRING, using PROVIDER."
  `((model . ,(llm-gemini-embedding-model provider))
    (content . ((parts . (((text . ,string))))))))

(defun llm-gemini--embedding-response-handler (response)
  "Handle the embedding RESPONSE from Gemini."
  (assoc-default 'values (assoc-default 'embedding response)))

(cl-defmethod llm-embedding ((provider llm-gemini) string)
  (llm-vertex--handle-response
   (llm-request-sync (llm-gemini--embedding-url provider)
                     :data (llm-gemini--embedding-request provider string))
   #'llm-gemini--embedding-response-handler))

(cl-defmethod llm-embedding-async ((provider llm-gemini) string vector-callback error-callback)
  (let ((buf (current-buffer)))
    (llm-request-async (llm-gemini--embedding-url provider)
                       :data (llm-gemini--embedding-request provider string)
                       :on-success (lambda (data)
                                     (llm-request-callback-in-buffer
                                      buf vector-callback (llm-gemini--embedding-response-handler data)))
                       :on-error (lambda (_ data)
                                   (llm-request-callback-in-buffer
                                    buf error-callback
                                    'error (llm-vertex--error-message data))))))

(defun llm-gemini--chat-url (provider)
  "Return the URL for the chat request, using PROVIDER."
  (format "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s"
          (llm-gemini-chat-model provider)
          (llm-gemini-key provider)))

(defun llm-gemini--get-chat-response (response)
  "Get the chat response from RESPONSE."
  ;; Response is a series of the form "text: <some text>\n", which we will concatenate.
  (mapconcat (lambda (x) (read (substring-no-properties (string-trim x) 8))) (split-string response "\n" t "\\s*") ""))

(cl-defmethod llm-chat ((provider llm-gemini) prompt)
  (let ((response (llm-vertex--get-chat-response-streaming
                   (llm-request-sync (llm-gemini--chat-url provider)
                                     :data (llm-vertex--chat-request-streaming prompt)))))
    (setf (llm-chat-prompt-interactions prompt)
          (append (llm-chat-prompt-interactions prompt)
                  (list (make-llm-chat-prompt-interaction :role 'assistant :content response))))
    response))

(cl-defmethod llm-chat-streaming ((provider llm-gemini) prompt partial-callback response-callback error-callback)
  (let ((buf (current-buffer)))
    (llm-request-async (llm-gemini--chat-url provider)
                       :data (llm-vertex--chat-request-streaming prompt)
                       :on-partial (lambda (partial)
                                     (when-let ((response (llm-vertex--get-partial-chat-ui-repsonse partial)))
                                       (llm-request-callback-in-buffer buf partial-callback response)))
                       :on-success (lambda (data)
                                     (let ((response (llm-vertex--get-chat-response-streaming data)))
                                     (setf (llm-chat-prompt-interactions prompt)
                                           (append (llm-chat-prompt-interactions prompt)
                                                   (list (make-llm-chat-prompt-interaction :role 'assistant :content response))))
                                     (llm-request-callback-in-buffer buf response-callback response)))
                       :on-error (lambda (_ data)
                                 (llm-request-callback-in-buffer buf error-callback 'error
                                                                 (llm-vertex--error-message data))))))

(defun llm-gemini--count-token-url (provider)
  "Return the URL for the count token call, using PROVIDER."
  (format "https://generativelanguage.googleapis.com/v1beta/models/%s:countTokens?key=%s"
          (llm-gemini-chat-model provider)
          (llm-gemini-key provider)))

(cl-defmethod llm-count-tokens ((provider llm-gemini) string)
  (llm-vertex--handle-response
   (llm-request-sync (llm-gemini--count-token-url provider)
                     :data (llm-vertex--to-count-token-request (llm-vertex--chat-request-streaming (llm-make-simple-chat-prompt string))))
   #'llm-vertex--count-tokens-extract-response))

(provide 'llm-gemini)

;;; llm-gemini.el ends here
