Test `melange.runtime_deps` in a private library

  $ cat > dune-project <<EOF
  > (lang dune 3.7)
  > (using melange 0.1)
  > EOF

  $ cat > dune <<EOF
  > (melange.emit
  >  (target output)
  >  (alias mel)
  >  (libraries foo)
  >  (runtime_deps assets/file.txt))
  > EOF

  $ mkdir lib
  $ echo "Some text" > lib/index.txt
  $ cat > lib/dune <<EOF
  > (library
  >  (name foo)
  >  (modes melange)
  >  (melange.runtime_deps index.txt))
  > EOF
  $ cat > lib/foo.ml <<EOF
  > let dirname = [%bs.raw "__dirname"]
  > let file_path = "./index.txt"
  > let read_asset () = Node.Fs.readFileSync (dirname ^ "/" ^ file_path) \`utf8
  > EOF

  $ mkdir assets
  $ cat > assets/file.txt <<EOF
  > hello from file
  > EOF

  $ cat > main.ml <<EOF
  > let dirname = [%bs.raw "__dirname"]
  > let file_path = "./assets/file.txt"
  > let file_content = Node.Fs.readFileSync (dirname ^ "/" ^ file_path) \`utf8
  > let () = Js.log file_content
  > let () = Js.log (Foo.read_asset ())
  > EOF

  $ mkdir -p output/lib
  $ dune build @mel

The runtime_dep index.txt was copied to the library build folder

  $ ls _build/default/lib
  foo.ml
  index.txt

The runtime_dep index.txt was copied to the build folder

  $ ls _build/default/output/lib
  foo.js
  index.txt
  $ node _build/default/output/main.js
  hello from file
  
  Some text
  
