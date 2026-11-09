package pi

// Line は、プルアップされたフックの接点である。0 が閉じ、1 が開いている。
type Line interface {
	// Value は、今のレベルである。
	Value() (int, error)
	// Changes は、レベルが変わったときに新しいレベルを渡す。
	Changes() <-chan int
	Close() error
}
