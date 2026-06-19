(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)
(require 'org-mem)

(defun org-node-roam-ql--param-value (params key)
  (let ((tail params)
        (result nil)
        (found nil))
    (while (and (consp tail) (not found))
      (if (eq (car tail) key)
          (progn
            (setq result (cadr tail))
            (setq found t))
        (setq tail (cdr tail))))
    result))

(defun org-node-roam-ql--read (value fallback)
  (cond
   ((null value) fallback)
   ((not (stringp value)) value)
   ((string-empty-p value) fallback)
   (t (car (read-from-string value)))))

(defun org-node-roam-ql--param (params key fallback)
  (org-node-roam-ql--read
   (org-node-roam-ql--param-value params key)
   fallback))

(defun org-node-roam-ql--symbol-param (params key fallback)
  (let ((value (org-node-roam-ql--param params key fallback)))
    (cond
     ((symbolp value) value)
     ((stringp value) (intern value))
     (t fallback))))

(defun org-node-roam-ql--entries (scope)
  (pcase scope
    ('nodes (org-mem-all-id-nodes))
    (_ (org-mem-all-entries))))

(defun org-node-roam-ql--tag (tag)
  (replace-regexp-in-string "\\`:\\|:\\'" "" (format "%s" tag)))

(defun org-node-roam-ql--tags (entry)
  (mapcar #'org-node-roam-ql--tag (org-mem-entry-tags entry)))

(defun org-node-roam-ql--tag-string (entry)
  (let ((tags (org-node-roam-ql--tags entry)))
    (if tags
        (concat ":" (string-join tags ":") ":")
      "")))

(defun org-node-roam-ql--string (value)
  (cond
   ((null value) "")
   ((stringp value) value)
   ((numberp value) (number-to-string value))
   (t (format "%s" value))))

(defun org-node-roam-ql--property (entry name)
  (let* ((key (format "%s" name))
         (upper-key (upcase key)))
    (pcase key
      ("title" (org-mem-entry-title entry))
      ("file" (org-mem-entry-file-truename entry))
      ("id" (org-mem-entry-id entry))
      ("todo" (org-mem-entry-todo-state entry))
      ("priority" (org-mem-entry-priority entry))
      ("tags" (string-join (org-node-roam-ql--tags entry) ":"))
      (_
       (or
        (org-mem-entry-property-with-inheritance key entry)
        (org-mem-entry-property-with-inheritance upper-key entry)
        (org-mem-entry-property key entry)
        (org-mem-entry-property upper-key entry))))))

(defun org-node-roam-ql--like (actual expected)
  (let ((case-fold-search t))
    (string-match-p
     (regexp-quote (org-node-roam-ql--string expected))
     (org-node-roam-ql--string actual))))

(defun org-node-roam-ql--match (entry query)
  (pcase query
    ((pred null) t)
    ('all t)
    (`(all) t)
    (`(and . ,items)
     (cl-every
      (lambda (item)
        (org-node-roam-ql--match entry item))
      items))
    (`(or . ,items)
     (seq-some
      (lambda (item)
        (org-node-roam-ql--match entry item))
      items))
    (`(not ,item)
     (not (org-node-roam-ql--match entry item)))
    (`(tag ,tag)
     (member (org-node-roam-ql--tag tag) (org-node-roam-ql--tags entry)))
    (`(tags . ,tags)
     (cl-every
      (lambda (tag)
        (member (org-node-roam-ql--tag tag) (org-node-roam-ql--tags entry)))
      tags))
    (`(properties ,name ,value)
     (string=
      (org-node-roam-ql--string (org-node-roam-ql--property entry name))
      (org-node-roam-ql--string value)))
    (`(property ,name ,value)
     (string=
      (org-node-roam-ql--string (org-node-roam-ql--property entry name))
      (org-node-roam-ql--string value)))
    (`(properties~ ,name ,value)
     (org-node-roam-ql--like
      (org-node-roam-ql--property entry name)
      value))
    (`(property~ ,name ,value)
     (org-node-roam-ql--like
      (org-node-roam-ql--property entry name)
      value))
    (`(title ,value)
     (org-node-roam-ql--like (org-mem-entry-title entry) value))
    (`(file ,value)
     (org-node-roam-ql--like (org-mem-entry-file-truename entry) value))
    (`(todo ,value)
     (string=
      (org-node-roam-ql--string (org-mem-entry-todo-state entry))
      (org-node-roam-ql--string value)))
    (`(priority ,value)
     (string=
      (org-node-roam-ql--string (org-mem-entry-priority entry))
      (org-node-roam-ql--string value)))
    (_ nil)))

(defun org-node-roam-ql--query (params)
  (let ((query (org-node-roam-ql--param params :query nil))
        (include (org-node-roam-ql--param params :include nil))
        (exclude (org-node-roam-ql--param params :exclude nil)))
    (or query
        (cond
         ((and include exclude) `(and ,include (not ,exclude)))
         (include include)
         (exclude `(not ,exclude))
         (t 'all)))))

(defun org-node-roam-ql--entry-link (entry)
  (if-let ((id (org-mem-entry-id entry)))
      (org-link-make-string
       (concat "id:" id)
       (org-mem-entry-title entry))
    (org-link-make-string
     (format "file:%s::%d"
             (org-link-escape (org-mem-entry-file-truename entry))
             (org-mem-entry-lnum entry))
     (org-mem-entry-title entry))))

(defun org-node-roam-ql--file-link (entry)
  (let ((file (org-mem-entry-file-truename entry)))
    (org-link-make-string
     (concat "file:" (org-link-escape file))
     (file-name-base file))))

(defun org-node-roam-ql--unique-files (entries)
  (let ((files nil)
        (result nil))
    (dolist (entry entries)
      (let ((file (org-mem-entry-file-truename entry)))
        (unless (member file files)
          (push file files)
          (push entry result))))
    (nreverse result)))

(defun org-node-roam-ql--custom-column-p (column)
  (and
   (consp column)
   (consp (car column))
   (cdr column)
   (null (cddr column))))

(defun org-node-roam-ql--normalize-column (column)
  (if (stringp column)
      (intern column)
    column))

(defun org-node-roam-ql--column-expr (column)
  (if (org-node-roam-ql--custom-column-p column)
      (car column)
    (org-node-roam-ql--normalize-column column)))

(defun org-node-roam-ql--column-title (column)
  (cond
   ((org-node-roam-ql--custom-column-p column)
    (org-node-roam-ql--string (cadr column)))
   ((and (consp column) (eq (car column) 'property))
    (org-node-roam-ql--string (cadr column)))
   ((symbolp column)
    (capitalize (symbol-name column)))
   ((stringp column)
    (capitalize column))
   (t
    (org-node-roam-ql--string column))))

(defun org-node-roam-ql--entry-column-value (entry column)
  (pcase (org-node-roam-ql--column-expr column)
    ('link (org-node-roam-ql--entry-link entry))
    ('title (org-mem-entry-title entry))
    ('file (abbreviate-file-name (org-mem-entry-file-truename entry)))
    ('id (or (org-mem-entry-id entry) ""))
    ('tags (string-join (org-node-roam-ql--tags entry) ":"))
    ('todo (or (org-mem-entry-todo-state entry) ""))
    ('priority (or (org-mem-entry-priority entry) ""))
    (`(property ,name) (or (org-node-roam-ql--property entry name) ""))
    ((pred symbolp) (or (org-node-roam-ql--property entry column) ""))
    (_ "")))

(defun org-node-roam-ql--file-column-value (entry column)
  (pcase (org-node-roam-ql--column-expr column)
    ('link (org-node-roam-ql--file-link entry))
    ('title (file-name-base (org-mem-entry-file-truename entry)))
    ('file (abbreviate-file-name (org-mem-entry-file-truename entry)))
    (_ (org-node-roam-ql--entry-column-value entry column))))

(defun org-node-roam-ql--cell (value)
  (replace-regexp-in-string "|" "\\vert{}" (org-node-roam-ql--string value) t t))

(defun org-node-roam-ql--sort-value (entry column result)
  (if (eq result 'files)
      (org-node-roam-ql--file-column-value entry column)
    (org-node-roam-ql--entry-column-value entry column)))

(defun org-node-roam-ql--sort (entries column result)
  (if column
      (sort entries
            (lambda (left right)
              (string-lessp
               (org-node-roam-ql--string
                (org-node-roam-ql--sort-value left column result))
               (org-node-roam-ql--string
                (org-node-roam-ql--sort-value right column result)))))
    entries))

(defun org-node-roam-ql--take (entries take)
  (cond
   ((and (integerp take) (> take 0))
    (seq-take entries take))
   ((and (integerp take) (< take 0))
    (last entries (- take)))
   (t entries)))

(defun org-node-roam-ql--list-link (entry result)
  (if (eq result 'files)
      (org-node-roam-ql--file-link entry)
    (org-node-roam-ql--entry-link entry)))

(defun org-node-roam-ql--list-line (entry result show-tags indent)
  (insert
   (format "%s- %s%s\n"
           indent
           (org-node-roam-ql--list-link entry result)
           (if show-tags
               (let ((tags (org-node-roam-ql--tag-string entry)))
                 (if (string-empty-p tags)
                     ""
                   (concat " " tags)))
             ""))))

(defun org-node-roam-ql--group-key (entry group-by result)
  (let ((value (org-node-roam-ql--sort-value entry group-by result)))
    (if (string-empty-p (org-node-roam-ql--string value))
        "No group"
      (org-node-roam-ql--string value))))

(defun org-node-roam-ql--groups (entries group-by result)
  (let ((groups nil))
    (dolist (entry entries)
      (let* ((key (org-node-roam-ql--group-key entry group-by result))
             (group (assoc key groups)))
        (if group
            (setcdr group (cons entry (cdr group)))
          (push (cons key (list entry)) groups))))
    (mapcar
     (lambda (group)
       (cons (car group) (nreverse (cdr group))))
     (nreverse groups))))

(defun org-node-roam-ql--insert-list (entries result show-tags group-by)
  (if group-by
      (dolist (group (org-node-roam-ql--groups entries group-by result))
        (insert (format "- %s\n" (car group)))
        (dolist (entry (cdr group))
          (org-node-roam-ql--list-line entry result show-tags "  ")))
    (dolist (entry entries)
      (org-node-roam-ql--list-line entry result show-tags ""))))

(defun org-node-roam-ql--insert-table (entries columns value-function)
  (insert "| ")
  (insert (mapconcat #'org-node-roam-ql--column-title columns " | "))
  (insert " |\n|-\n")
  (dolist (entry entries)
    (insert "| ")
    (insert
     (mapconcat
      (lambda (column)
        (org-node-roam-ql--cell
         (funcall value-function entry column)))
      columns
      " | "))
    (insert " |\n"))
  (org-table-align))

(defun org-node-roam-ql--params-debug-message (params)
  (message "org-node-roam-ql params: %S" params))

(defun org-node-roam-ql-dblock (params)
  (let* ((scope (org-node-roam-ql--symbol-param params :scope 'entries))
         (query (org-node-roam-ql--query params))
         (columns (org-node-roam-ql--param params :columns '(link file tags)))
         (format-value (org-node-roam-ql--symbol-param params :format 'table))
         (result (org-node-roam-ql--symbol-param params :result 'entries))
         (sort-column (org-node-roam-ql--param params :sort 'title))
         (take (org-node-roam-ql--param params :take nil))
         (show-tags (org-node-roam-ql--param params :show-tags nil))
         (group-by (org-node-roam-ql--param params :group-by nil))
         (matched-entries
          (seq-filter
           (lambda (entry)
             (org-node-roam-ql--match entry query))
           (org-node-roam-ql--entries scope)))
         (result-entries
          (if (eq result 'files)
              (org-node-roam-ql--unique-files matched-entries)
            matched-entries))
         (sorted-entries
          (org-node-roam-ql--sort result-entries sort-column result))
         (final-entries
          (org-node-roam-ql--take sorted-entries take)))
    (pcase (list result format-value)
      (`(files list)
       (org-node-roam-ql--insert-list final-entries 'files show-tags group-by))
      (`(files ,_)
       (org-node-roam-ql--insert-table
        final-entries
        columns
        #'org-node-roam-ql--file-column-value))
      (`(_ list)
       (org-node-roam-ql--insert-list final-entries 'entries show-tags group-by))
      (_
       (org-node-roam-ql--insert-table
        final-entries
        columns
        #'org-node-roam-ql--entry-column-value)))))

(defun org-dblock-write:org-node-roam-ql (params)
  (org-node-roam-ql-dblock params))

(defun org-dblock-write:org-roam-ql (params)
  (org-node-roam-ql-dblock params))

(provide 'org-node-roam-ql)
