begin_fold() {
  local tag="$1"
  echo "%%%FOLD {${tag}}%%%" 1>&2
  set -x
}

end_fold() {
  set +x
  echo "%%%END FOLD%%%" 1>&2
}
