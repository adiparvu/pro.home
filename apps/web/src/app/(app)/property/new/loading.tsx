export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6 animate-pulse">
      <div className="h-8 w-36 rounded-xl glass-light" />
      <div className="h-10 rounded-xl glass-light" />
      <div className="grid grid-cols-2 gap-2">
        <div className="h-10 rounded-xl glass-light" />
        <div className="h-10 rounded-xl glass-light" />
      </div>
      <div className="h-10 rounded-xl glass-light" />
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
        <div className="h-10 rounded-xl glass-light" />
        <div className="h-10 rounded-xl glass-light" />
        <div className="h-10 rounded-xl glass-light" />
      </div>
      <div className="h-10 w-32 rounded-xl glass-light ml-auto" />
    </div>
  )
}
