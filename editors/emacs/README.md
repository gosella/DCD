#Emacs Integration

##Requirements
* You must have the [auto-complete](https://github.com/auto-complete/auto-complete) package.
[yasnippet](https://github.com/capitaomorte/yasnippet) and [popwin](https://github.com/m2ym/popwin-el) is recommended.
* Make sure dcd-client and dcd-server is in your exec-path. Otherwise, please set the variable ```dcd-exectutable``` and ```dcd-server-executable``` using ```M-x customize```.

## Setup
* First, follow the Setup section in the root README.
* Second, add the following to your .emacs. With this setting, dcd-server starts automatically when you open file in d-mode.  (Of course, you should edit ```path_to_ac-dcd.el``` to suit your enviroment.)

```
;;; ac-dcd
(add-to-list 'load-path "path_to_ac-dcd.el")
(require 'ac-dcd)
(add-to-list 'ac-modes 'd-mode)

(add-hook 'd-mode-hook
		  '(lambda () "set up ac-dcd"
			 (ac-dcd-maybe-start-server)
			 (add-to-list 'ac-sources 'ac-source-dcd)))

(define-key d-mode-map (kbd "C-c ?") 'ac-dcd-show-ddoc-with-buffer)
(define-key d-mode-map (kbd "C-c .") 'ac-dcd-goto-definition)
(define-key d-mode-map (kbd "C-c ,") 'ac-dcd-goto-def-pop-marker)

(when (featurep 'popwin)
  (add-to-list 'popwin:special-display-config
			   `(,ac-dcd-error-buffer-name :noselect t))
  (add-to-list 'popwin:special-display-config
				 `(,ac-dcd-document-buffer-name :position right :width 80)))

```

* Third, set import path using ```M-x customize-variable RET ac-dcd-flags```.
* When something is wrong, please check variables with ```M-x customize-apropos RET ac-dcd``` and restart server with ```M-x ac-dcd-init-server```.

## Features
* Dlang source for auto-complete
* Function calltip expansion with yasnippet
* Show ddoc with ```C-c ?```
* Goto definition with ```C-c .```
* After goto definition, you can pop to previous position with ```C-c ,```

## TODO
* Multi byte character support (Need help!)
